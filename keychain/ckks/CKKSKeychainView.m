/*
 * Copyright (c) 2016 Apple Inc. All Rights Reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 *
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 *
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 *
 * @APPLE_LICENSE_HEADER_END@
 */

#import "CKKSKeychainView.h"



#if OCTAGON
#import "CloudKitDependencies.h"
#import <CloudKit/CloudKit.h>
#import <CloudKit/CloudKit_Private.h>
#endif

#import "CKKS.h"
#import "OctagonAPSReceiver.h"
#import "CKKSIncomingQueueEntry.h"
#import "CKKSOutgoingQueueEntry.h"
#import "CKKSCurrentKeyPointer.h"
#import "CKKSKey.h"
#import "CKKSMirrorEntry.h"
#import "CKKSZoneStateEntry.h"
#import "CKKSItemEncrypter.h"
#import "CKKSIncomingQueueOperation.h"
#import "CKKSNewTLKOperation.h"
#import "CKKSProcessReceivedKeysOperation.h"
#import "CKKSZone.h"
#import "CKKSFetchAllRecordZoneChangesOperation.h"
#import "CKKSHealKeyHierarchyOperation.h"
#import "CKKSReencryptOutgoingItemsOperation.h"
#import "CKKSScanLocalItemsOperation.h"
#import "CKKSSynchronizeOperation.h"
#import "CKKSRateLimiter.h"
#import "CKKSManifest.h"
#import "CKKSManifestLeafRecord.h"
#import "CKKSZoneChangeFetcher.h"
#import "CKKSAnalytics.h"
#import "keychain/analytics/CKKSLaunchSequence.h"
#import "keychain/ckks/CKKSCloudKitClassDependencies.h"
#import "keychain/ckks/CKKSDeviceStateEntry.h"
#import "keychain/ckks/CKKSNearFutureScheduler.h"
#import "keychain/ckks/CKKSCurrentItemPointer.h"
#import "keychain/ckks/CKKSUpdateCurrentItemPointerOperation.h"
#import "keychain/ckks/CKKSUpdateDeviceStateOperation.h"
#import "keychain/ckks/CKKSNotifier.h"
#import "keychain/ckks/CloudKitCategories.h"
#import "keychain/ckks/CKKSTLKShareRecord.h"
#import "keychain/ckks/CKKSHealTLKSharesOperation.h"
#import "keychain/ckks/CKKSLocalSynchronizeOperation.h"
#import "keychain/ckks/CKKSPeerProvider.h"
#import "keychain/categories/NSError+UsefulConstructors.h"

#import "keychain/ot/OTConstants.h"
#import "keychain/ot/OTDefines.h"
#import "keychain/ot/OctagonCKKSPeerAdapter.h"
#import "keychain/ot/ObjCImprovements.h"

#include <utilities/SecCFWrappers.h>
#include <utilities/SecTrace.h>
#include <utilities/SecDb.h>
#include "keychain/securityd/SecDbItem.h"
#include "keychain/securityd/SecItemDb.h"
#include "keychain/securityd/SecItemSchema.h"
#include "keychain/securityd/SecItemServer.h"
#include <utilities/debugging.h>
#include <Security/SecItemPriv.h>
#include "keychain/SecureObjectSync/SOSAccountTransaction.h"
#include <utilities/SecADWrapper.h>
#include <utilities/SecPLWrappers.h>
#include <os/transaction_private.h>

#if OCTAGON

@interface CKKSKeychainView()
@property bool keyStateFetchRequested;
@property bool keyStateProcessRequested;
@property bool trustedPeersSetChanged;

@property bool keyStateCloudKitDeleteRequested;
@property NSHashTable<CKKSResultOperation*>* cloudkitDeleteZoneOperations;

@property bool keyStateLocalResetRequested;
@property NSHashTable<CKKSResultOperation*>* localResetOperations;

@property bool tlkCreationRequested;
@property NSHashTable<CKKSResultOperation<CKKSKeySetProviderOperationProtocol>*>* keysetProviderOperations;


@property (atomic) NSString *activeTLK;

@property (readonly) Class<CKKSNotifier> notifierClass;

// Slows down all outgoing queue operations
@property CKKSNearFutureScheduler* outgoingQueueOperationScheduler;

@property CKKSResultOperation* processIncomingQueueAfterNextUnlockOperation;
@property CKKSResultOperation* resultsOfNextIncomingQueueOperationOperation;

@property NSMutableDictionary<NSString*, SecBoolNSErrorCallback>* pendingSyncCallbacks;

// An extra queue for semaphore-waiting-based NSOperations
@property NSOperationQueue* waitingQueue;

// Scratch space for resyncs
@property (nullable) NSMutableSet<NSString*>* resyncRecordsSeen;

// Make these readwrite
@property NSArray<id<CKKSPeerProvider>>* currentPeerProviders;
@property NSArray<CKKSPeerProviderState*>* currentTrustStates;

@end
#endif

@implementation CKKSKeychainView
#if OCTAGON

- (instancetype)initWithContainer:(CKContainer*)container
                         zoneName:(NSString*)zoneName
                   accountTracker:(CKKSAccountStateTracker*)accountTracker
                 lockStateTracker:(CKKSLockStateTracker*)lockStateTracker
              reachabilityTracker:(CKKSReachabilityTracker*)reachabilityTracker
                    changeFetcher:(CKKSZoneChangeFetcher*)fetcher
                     zoneModifier:(CKKSZoneModifier*)zoneModifier
                 savedTLKNotifier:(CKKSNearFutureScheduler*)savedTLKNotifier
        cloudKitClassDependencies:(CKKSCloudKitClassDependencies*)cloudKitClassDependencies
{

    if(self = [super initWithContainer:container
                              zoneName:zoneName
                        accountTracker:accountTracker
                   reachabilityTracker:reachabilityTracker
                          zoneModifier:zoneModifier
             cloudKitClassDependencies:cloudKitClassDependencies]) {
        WEAKIFY(self);

        _loggedIn = [[CKKSCondition alloc] init];
        _loggedOut = [[CKKSCondition alloc] init];
        _accountStateKnown = [[CKKSCondition alloc] init];

        _trustStatus = CKKSAccountStatusUnknown;
        _trustDependency = [CKKSResultOperation named:@"wait-for-trust" withBlock:^{}];

        _incomingQueueOperations = [NSHashTable weakObjectsHashTable];
        _outgoingQueueOperations = [NSHashTable weakObjectsHashTable];
        _cloudkitDeleteZoneOperations = [NSHashTable weakObjectsHashTable];
        _localResetOperations = [NSHashTable weakObjectsHashTable];
        _keysetProviderOperations = [NSHashTable weakObjectsHashTable];

        _currentPeerProviders = @[];
        _currentTrustStates = @[];

        _launch = [[CKKSLaunchSequence alloc] initWithRocketName:@"com.apple.security.ckks.launch"];
        [_launch addAttribute:@"view" value:zoneName];

        _zoneChangeFetcher = fetcher;
        [fetcher registerClient:self];

        _resyncRecordsSeen = nil;

        _notifierClass = cloudKitClassDependencies.notifierClass;
        _notifyViewChangedScheduler = [[CKKSNearFutureScheduler alloc] initWithName:[NSString stringWithFormat: @"%@-notify-scheduler", self.zoneName]
                                                            initialDelay:250*NSEC_PER_MSEC
                                                         continuingDelay:1*NSEC_PER_SEC
                                                        keepProcessAlive:true
                                                          dependencyDescriptionCode:CKKSResultDescriptionPendingViewChangedScheduling
                                                                   block:^{
                                                                       STRONGIFY(self);
                                                                       [self.notifierClass post:[NSString stringWithFormat:@"com.apple.security.view-change.%@", self.zoneName]];

                                                                       // Ugly, but: the Manatee and Engram views need to send a fake 'PCS' view change.
                                                                       // TODO: make this data-driven somehow
                                                                       if([self.zoneName isEqualToString:@"Manatee"] ||
                                                                          [self.zoneName isEqualToString:@"Engram"] ||
                                                                          [self.zoneName isEqualToString:@"ApplePay"] ||
                                                                          [self.zoneName isEqualToString:@"Home"] ||
                                                                          [self.zoneName isEqualToString:@"LimitedPeersAllowed"]) {
                                                                           [self.notifierClass post:@"com.apple.security.view-change.PCS"];
                                                                       }
                                                                   }];

        _notifyViewReadyScheduler = [[CKKSNearFutureScheduler alloc] initWithName:[NSString stringWithFormat: @"%@-ready-scheduler", self.zoneName]
                                                                       initialDelay:250*NSEC_PER_MSEC
                                                                    continuingDelay:120*NSEC_PER_SEC
                                                                   keepProcessAlive:true
                                                          dependencyDescriptionCode:CKKSResultDescriptionPendingViewChangedScheduling
                                                                              block:^{
                                                                                  STRONGIFY(self);
                                                                                  NSDistributedNotificationCenter *center = [self.cloudKitClassDependencies.nsdistributednotificationCenterClass defaultCenter];

                                                                                  [center postNotificationName:@"com.apple.security.view-become-ready"
                                                                                                        object:nil
                                                                                                      userInfo:@{ @"view" : self.zoneName ?: @"unknown" }
                                                                                                       options:0];
                                                                              }];


        _pendingSyncCallbacks = [[NSMutableDictionary alloc] init];

        _lockStateTracker = lockStateTracker;
        _savedTLKNotifier = savedTLKNotifier;

        _keyHierarchyConditions = [[NSMutableDictionary alloc] init];
        [CKKSZoneKeyStateMap() enumerateKeysAndObjectsUsingBlock:^(CKKSZoneKeyState * _Nonnull key, NSNumber * _Nonnull obj, BOOL * _Nonnull stop) {
            [self.keyHierarchyConditions setObject: [[CKKSCondition alloc] init] forKey:key];
        }];

        // Use the keyHierarchyState setter to modify the zone key state map
        self.keyHierarchyState = SecCKKSZoneKeyStateLoggedOut;

        _keyHierarchyError = nil;
        _keyHierarchyOperationGroup = nil;
        _keyStateMachineOperation = nil;
        _keyStateFetchRequested = false;
        _keyStateProcessRequested = false;
        _tlkCreationRequested = false;

        _waitingQueue = [[NSOperationQueue alloc] init];
        _waitingQueue.maxConcurrentOperationCount = 5;

        _keyStateReadyDependency = [self createKeyStateReadyDependency: @"Key state has become ready for the first time." ckoperationGroup:[CKOperationGroup CKKSGroupWithName:@"initial-key-state-ready-scan"]];

        _keyStateNonTransientDependency = [self createKeyStateNontransientDependency];

        dispatch_time_t initialOutgoingQueueDelay = SecCKKSReduceRateLimiting() ? NSEC_PER_MSEC * 200 : NSEC_PER_SEC * 1;
        dispatch_time_t continuingOutgoingQueueDelay = SecCKKSReduceRateLimiting() ? NSEC_PER_MSEC * 200 : NSEC_PER_SEC * 30;
        _outgoingQueueOperationScheduler = [[CKKSNearFutureScheduler alloc] initWithName:[NSString stringWithFormat: @"%@-outgoing-queue-scheduler", self.zoneName]
                                                                            initialDelay:initialOutgoingQueueDelay
                                                                         continuingDelay:continuingOutgoingQueueDelay
                                                                        keepProcessAlive:false
                                                               dependencyDescriptionCode:CKKSResultDescriptionPendingOutgoingQueueScheduling
                                                                                   block:^{}];


        dispatch_time_t initialKeyHierachyPokeDelay = SecCKKSReduceRateLimiting() ? NSEC_PER_MSEC * 100 : NSEC_PER_MSEC * 500;
        dispatch_time_t continuingKeyHierachyPokeDelay = SecCKKSReduceRateLimiting() ? NSEC_PER_MSEC * 200 : NSEC_PER_SEC * 5;
        _pokeKeyStateMachineScheduler = [[CKKSNearFutureScheduler alloc] initWithName:[NSString stringWithFormat: @"%@-reprocess-scheduler", self.zoneName]
                                                                         initialDelay:initialKeyHierachyPokeDelay
                                                                      continuingDelay:continuingKeyHierachyPokeDelay
                                                                     keepProcessAlive:true
                                                            dependencyDescriptionCode:CKKSResultDescriptionPendingKeyHierachyPokeScheduling
                                                                                     block:^{
                                                                                         STRONGIFY(self);
                                                                                         [self dispatchSyncWithAccountKeys: ^bool{
                                                                                             STRONGIFY(self);

                                                                                             [self _onqueueAdvanceKeyStateMachineToState:nil withError:nil];
                                                                                             return true;
                                                                                         }];
                                                                                     }];
    }
    return self;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"<%@: %@ (%@)>", NSStringFromClass([self class]), self.zoneName, self.keyHierarchyState];
}

- (NSString*)debugDescription {
    return [NSString stringWithFormat:@"<%@: %@ (%@) %p>", NSStringFromClass([self class]), self.zoneName, self.keyHierarchyState, self];
}

- (CKKSZoneKeyState*)keyHierarchyState {
    return _keyHierarchyState;
}

- (void)setKeyHierarchyState:(CKKSZoneKeyState *)keyHierarchyState {
    if((keyHierarchyState == nil && _keyHierarchyState == nil) || ([keyHierarchyState isEqualToString:_keyHierarchyState])) {
        // No change, do nothing.
    } else {
        // Fixup the condition variables as part of setting this state
        if(_keyHierarchyState) {
            self.keyHierarchyConditions[_keyHierarchyState] = [[CKKSCondition alloc] init];
        }

        _keyHierarchyState = keyHierarchyState;

        if(keyHierarchyState) {
            [self.keyHierarchyConditions[keyHierarchyState] fulfill];
        }
    }
}

- (NSString *)lastActiveTLKUUID
{
    return self.activeTLK;
}

- (void)_onqueueResetSetup:(CKKSZoneKeyState*)newState resetMessage:(NSString*)resetMessage ckoperationGroup:(CKOperationGroup*)group {
    [super resetSetup];

    self.keyHierarchyState = newState;
    self.keyHierarchyError = nil;

    [self.keyStateMachineOperation cancel];
    self.keyStateMachineOperation = nil;

    self.keyStateFetchRequested = false;
    self.keyStateProcessRequested = false;

    self.keyHierarchyOperationGroup = group;

    [self ensureKeyStateReadyDependency:resetMessage];

    NSOperation* oldKSNTD = self.keyStateNonTransientDependency;
    self.keyStateNonTransientDependency = [self createKeyStateNontransientDependency];
    if(oldKSNTD) {
        [oldKSNTD addDependency:self.keyStateNonTransientDependency];
        [self.waitingQueue addOperation:oldKSNTD];
    }
}

- (void)ensureKeyStateReadyDependency:(NSString*)resetMessage {
    NSOperation* oldKSRD = self.keyStateReadyDependency;
    self.keyStateReadyDependency = [self createKeyStateReadyDependency:resetMessage ckoperationGroup:self.keyHierarchyOperationGroup];
    if(oldKSRD) {
        [oldKSRD addDependency:self.keyStateReadyDependency];
        [self.waitingQueue addOperation:oldKSRD];
    }
}

- (CKKSResultOperation*)createPendingInitializationOperation {

    WEAKIFY(self);
    CKKSResultOperation* initializationOp = [CKKSGroupOperation named:@"view-initialization" withBlockTakingSelf:^(CKKSGroupOperation * _Nonnull strongOp) {
        STRONGIFY(self);

        __block CKKSResultOperation* zoneCreationOperation = nil;
        [self dispatchSync:^bool {
            CKKSZoneStateEntry* ckse = [CKKSZoneStateEntry state: self.zoneName];
            zoneCreationOperation = [self handleCKLogin:ckse.ckzonecreated zoneSubscribed:ckse.ckzonesubscribed];
            return true;
        }];

        CKKSResultOperation* viewInitializationOperation = [CKKSResultOperation named:@"view-initialization" withBlockTakingSelf:^(CKKSResultOperation * _Nonnull strongInternalOp) {
            STRONGIFY(self);
            if(!self) {
                ckkserror("ckks", self, "received callback for released object");
                return;
            }

            [self dispatchSyncWithAccountKeys: ^bool {
                ckksnotice("ckks", self, "Zone setup progress: %@ %d %@ %d %@",
                           [CKKSAccountStateTracker stringFromAccountStatus:self.accountStatus],
                           self.zoneCreated, self.zoneCreatedError, self.zoneSubscribed, self.zoneSubscribedError);

                NSError* error = nil;
                CKKSZoneStateEntry* ckse = [CKKSZoneStateEntry state: self.zoneName];
                ckse.ckzonecreated = self.zoneCreated;
                ckse.ckzonesubscribed = self.zoneSubscribed;

                // Although, if the zone subscribed error says there's no zone, mark down that there's no zone
                if(self.zoneSubscribedError &&
                   [self.zoneSubscribedError.domain isEqualToString:CKErrorDomain] && self.zoneSubscribedError.code == CKErrorPartialFailure) {
                    NSError* subscriptionError = self.zoneSubscribedError.userInfo[CKPartialErrorsByItemIDKey][self.zoneID];
                    if(subscriptionError && [subscriptionError.domain isEqualToString:CKErrorDomain] && subscriptionError.code == CKErrorZoneNotFound) {

                        ckkserror("ckks", self, "zone subscription error appears to say the zone doesn't exist, fixing status: %@", self.zoneSubscribedError);
                        ckse.ckzonecreated = false;
                    }
                }

                [ckse saveToDatabase: &error];
                if(error) {
                    ckkserror("ckks", self, "couldn't save zone creation status for %@: %@", self.zoneName, error);
                }

                if(!self.zoneCreated || !self.zoneSubscribed) {
                    // Go into 'zonecreationfailed'
                    strongInternalOp.error = self.zoneCreatedError ? self.zoneCreatedError : self.zoneSubscribedError;
                    [self _onqueueAdvanceKeyStateMachineToState:SecCKKSZoneKeyStateZoneCreationFailed withError:strongInternalOp.error];

                    return true;
                } else {
                    [self _onqueueAdvanceKeyStateMachineToState:SecCKKSZoneKeyStateInitialized withError:nil];
                }

                return true;
            }];
        }];

        [viewInitializationOperation addDependency:zoneCreationOperation];
        [strongOp runBeforeGroupFinished:viewInitializationOperation];
    }];

    return initializationOp;
}

- (void)_onqueuePerformKeyStateInitialized:(CKKSZoneStateEntry*)ckse {
    CKKSOutgoingQueueOperation* outgoingOperation = nil;
    NSOperation* initialProcess = nil;

    // Check if we believe we've synced this zone before.
    if(ckse.changeToken == nil) {
        self.keyHierarchyOperationGroup = [CKOperationGroup CKKSGroupWithName:@"initial-setup"];

        ckksnotice("ckks", self, "No existing change token; going to try to match local items with CloudKit ones.");

        // Onboard this keychain: there's likely items in it that we haven't synced yet.
        // But, there might be items in The Cloud that correspond to these items, with UUIDs that we don't know yet.
        // First, fetch all remote items.
        CKKSResultOperation* fetch = [self.zoneChangeFetcher requestSuccessfulFetch:CKKSFetchBecauseInitialStart];
        fetch.name = @"initial-fetch";

        // Next, try to process them (replacing local entries)
        initialProcess = [self processIncomingQueue:true after:fetch];
        initialProcess.name = @"initial-process-incoming-queue";

        // If all that succeeds, iterate through all keychain items and find the ones which need to be uploaded
        self.initialScanOperation = [self scanLocalItems:@"initial-scan-operation"
                                        ckoperationGroup:self.keyHierarchyOperationGroup
                                                   after:initialProcess];

    } else {
        // Likely a restart of securityd!

        // First off, are there any in-flight queue entries? If so, put them back into New.
        // If they're truly in-flight, we'll "conflict" with ourselves, but that should be fine.
        NSError* error = nil;
        [self _onqueueResetAllInflightOQE:&error];
        if(error) {
            ckkserror("ckks", self, "Couldn't reset in-flight OQEs, bad behavior ahead: %@", error);
        }

        // Are there any fixups to run first?
        self.lastFixupOperation = [CKKSFixups fixup:ckse.lastFixup for:self];
        if(self.lastFixupOperation) {
            ckksnotice("ckksfixup", self, "We have a fixup to perform: %@", self.lastFixupOperation);
            [self scheduleOperation:self.lastFixupOperation];
        }

        self.keyHierarchyOperationGroup = [CKOperationGroup CKKSGroupWithName:@"restart-setup"];

        if ([CKKSManifest shouldSyncManifests]) {
            self.egoManifest = [CKKSEgoManifest tryCurrentEgoManifestForZone:self.zoneName];
        }

        // If it's been more than 24 hours since the last fetch, fetch and process everything.
        // Or, if we think we were interrupted in the middle of fetching, fetch some more.
        // Otherwise, just kick off the local queue processing.

        NSDate* now = [NSDate date];
        NSDateComponents* offset = [[NSDateComponents alloc] init];
        [offset setHour:-24];
        NSDate* deadline = [[NSCalendar currentCalendar] dateByAddingComponents:offset toDate:now options:0];

        if(ckse.lastFetchTime == nil ||
           [ckse.lastFetchTime compare: deadline] == NSOrderedAscending ||
           ckse.moreRecordsInCloudKit) {
            initialProcess = [self fetchAndProcessCKChanges:CKKSFetchBecauseSecuritydRestart after:self.lastFixupOperation];

            // Also, kick off a scan local items: it'll find any out-of-sync issues in the local keychain
            self.initialScanOperation = [self scanLocalItems:@"24-hr-scan-operation"
                                                ckoperationGroup:self.keyHierarchyOperationGroup
                                                       after:initialProcess];
        } else {
            initialProcess = [self processIncomingQueue:false after:self.lastFixupOperation];
        }

        if([CKKSManifest shouldSyncManifests]) {
            if (!self.egoManifest && !self.initialScanOperation) {
                ckksnotice("ckksmanifest", self, "No ego manifest on restart; rescanning");
                self.initialScanOperation = [self scanLocalItems:@"initial-scan-operation"
                                                ckoperationGroup:self.keyHierarchyOperationGroup
                                                           after:initialProcess];
            }
        }

        // Process outgoing queue after re-start
        outgoingOperation = [self processOutgoingQueueAfter:self.lastFixupOperation ckoperationGroup:self.keyHierarchyOperationGroup];
    }

    /*
     * Launch time is determined by when the zone have:
     *  1. keystate have become ready
     *  2. scan local items (if needed)
     *  3. processed all outgoing item (if needed)
     */

    WEAKIFY(self);
    NSBlockOperation *seemReady = [NSBlockOperation named:[NSString stringWithFormat:@"seemsReadyForSyncing-%@", self.zoneName] withBlock:^void{
        STRONGIFY(self);
        NSError *error = nil;
        ckksnotice("launch", self, "Launch complete");
        NSNumber *zoneSize = [CKKSMirrorEntry counts:self.zoneID error:&error];
        if (zoneSize) {
            zoneSize = @(SecBucket1Significant([zoneSize longValue]));
            [self.launch addAttribute:@"zonesize" value:zoneSize];
        }
        [self.launch launch];

        /*
         * Since we think we are ready, signal to CK that its to check for PCS identities again, and create the
         * since before we completed this operation, we would probably have failed with a timeout because
         * we where busy downloading items from CloudKit and then processing them.
         */
        [self.notifyViewReadyScheduler trigger];
    }];

    [seemReady addNullableDependency:self.keyStateReadyDependency];
    [seemReady addNullableDependency:outgoingOperation];
    [seemReady addNullableDependency:self.initialScanOperation];
    [seemReady addNullableDependency:initialProcess];

    [self scheduleOperation: seemReady];
}

- (bool)_onqueueResetLocalData: (NSError * __autoreleasing *) error {
    dispatch_assert_queue(self.queue);

    NSError* localerror = nil;
    bool setError = false; // Ugly, but this is the only way to return the first error given

    CKKSZoneStateEntry* ckse = [CKKSZoneStateEntry state: self.zoneName];
    ckse.ckzonecreated = false;
    ckse.ckzonesubscribed = false; // I'm actually not sure about this: can you be subscribed to a non-existent zone?
    ckse.changeToken = NULL;
    [ckse saveToDatabase: &localerror];
    if(localerror) {
        ckkserror("ckks", self, "couldn't reset zone status for %@: %@", self.zoneName, localerror);
        if(error && !setError) {
            *error = localerror; setError = true;
        }
    }

    [CKKSMirrorEntry deleteAll:self.zoneID error: &localerror];
    if(localerror) {
        ckkserror("ckks", self, "couldn't delete all CKKSMirrorEntry: %@", localerror);
        if(error && !setError) {
            *error = localerror; setError = true;
        }
    }

    [CKKSOutgoingQueueEntry deleteAll:self.zoneID error: &localerror];
    if(localerror) {
        ckkserror("ckks", self, "couldn't delete all CKKSOutgoingQueueEntry: %@", localerror);
        if(error && !setError) {
            *error = localerror; setError = true;
        }
    }

    [CKKSIncomingQueueEntry deleteAll:self.zoneID error: &localerror];
    if(localerror) {
        ckkserror("ckks", self, "couldn't delete all CKKSIncomingQueueEntry: %@", localerror);
        if(error && !setError) {
            *error = localerror; setError = true;
        }
    }

    [CKKSKey deleteAll:self.zoneID error: &localerror];
    if(localerror) {
        ckkserror("ckks", self, "couldn't delete all CKKSKey: %@", localerror);
        if(error && !setError) {
            *error = localerror; setError = true;
        }
    }

    [CKKSTLKShareRecord deleteAll:self.zoneID error: &localerror];
    if(localerror) {
        ckkserror("ckks", self, "couldn't delete all CKKSTLKShare: %@", localerror);
        if(error && !setError) {
            *error = localerror; setError = true;
        }
    }

    [CKKSCurrentKeyPointer deleteAll:self.zoneID error: &localerror];
    if(localerror) {
        ckkserror("ckks", self, "couldn't delete all CKKSCurrentKeyPointer: %@", localerror);
        if(error && !setError) {
            *error = localerror; setError = true;
        }
    }

    [CKKSCurrentItemPointer deleteAll:self.zoneID error: &localerror];
    if(localerror) {
        ckkserror("ckks", self, "couldn't delete all CKKSCurrentItemPointer: %@", localerror);
        if(error && !setError) {
            *error = localerror; setError = true;
        }
    }

    [CKKSDeviceStateEntry deleteAll:self.zoneID error:&localerror];
    if(localerror) {
        ckkserror("ckks", self, "couldn't delete all CKKSDeviceStateEntry: %@", localerror);
        if(error && !setError) {
            *error = localerror; setError = true;
        }
    }

    return (localerror == nil && !setError);
}

- (CKKSResultOperation*)createPendingResetLocalDataOperation {
    @synchronized(self.localResetOperations) {
        CKKSResultOperation* pendingResetLocalOperation = (CKKSResultOperation*) [self findFirstPendingOperation:self.localResetOperations];
        if(!pendingResetLocalOperation) {
            WEAKIFY(self);
            pendingResetLocalOperation = [CKKSResultOperation named:@"reset-local" withBlockTakingSelf:^(CKKSResultOperation * _Nonnull strongOp) {
                STRONGIFY(self);
                __block NSError* error = nil;

                [self dispatchSync: ^bool{
                    [self _onqueueResetLocalData: &error];
                    return true;
                }];

                strongOp.error = error;
            }];
            [pendingResetLocalOperation linearDependencies:self.localResetOperations];
        }
        return pendingResetLocalOperation;
    }
}

- (CKKSResultOperation*)resetLocalData {
    // Not overly thread-safe, but a single read is okay
    CKKSAccountStatus accountStatus = self.accountStatus;
    ckksnotice("ckksreset", self, "Requesting local data reset");

    // If we're currently signed in, the reset operation will be handled by the CKKS key state machine, and a reset should end up in 'ready'
    if(accountStatus == CKKSAccountStatusAvailable) {
        WEAKIFY(self);
        CKKSGroupOperation* resetOperationGroup = [CKKSGroupOperation named:@"local-reset" withBlockTakingSelf:^(CKKSGroupOperation *strongOp) {
            STRONGIFY(self);

            __block CKKSResultOperation* resetOperation = nil;

            [self dispatchSyncWithAccountKeys:^bool {
                self.keyStateLocalResetRequested = true;
                resetOperation = [self createPendingResetLocalDataOperation];
                [self _onqueueAdvanceKeyStateMachineToState:nil withError:nil];
                return true;
            }];

            [strongOp dependOnBeforeGroupFinished:resetOperation];
        }];
        [self scheduleOperationWithoutDependencies:resetOperationGroup];

        CKKSGroupOperation* viewReset = [CKKSGroupOperation named:@"local-data-reset" withBlockTakingSelf:^(CKKSGroupOperation *strongOp) {
            STRONGIFY(self);
            // Now that the local reset finished, wait for the key hierarchy state machine to churn
            ckksnotice("ckksreset", self, "waiting for key hierarchy to become nontransient (after local reset)");
            CKKSResultOperation* waitOp = [CKKSResultOperation named:@"waiting-for-local-reset" withBlock:^{}];
            [waitOp timeout: 60*NSEC_PER_SEC];
            [waitOp addNullableDependency:self.keyStateNonTransientDependency];

            [strongOp runBeforeGroupFinished:waitOp];
        }];
        [viewReset addSuccessDependency:resetOperationGroup];

        [self scheduleOperationWithoutDependencies:viewReset];
        return viewReset;
    } else {
        // Since we're logged out, we must run the reset ourselves
        WEAKIFY(self);
        CKKSResultOperation* pendingResetLocalOperation = [CKKSResultOperation named:@"reset-local"
                                                                 withBlockTakingSelf:^(CKKSResultOperation * _Nonnull strongOp) {
            STRONGIFY(self);
            __block NSError* error = nil;

            [self dispatchSync: ^bool{
                [self _onqueueResetLocalData: &error];
                return true;
            }];

            strongOp.error = error;
        }];
        [self scheduleOperationWithoutDependencies:pendingResetLocalOperation];
        return pendingResetLocalOperation;
    }
}

- (CKKSResultOperation*)createPendingDeleteZoneOperation:(CKOperationGroup*)operationGroup {
    @synchronized(self.cloudkitDeleteZoneOperations) {
        CKKSResultOperation* pendingDeleteOperation = (CKKSResultOperation*) [self findFirstPendingOperation:self.cloudkitDeleteZoneOperations];
        if(!pendingDeleteOperation) {
            pendingDeleteOperation = [self deleteCloudKitZoneOperation:operationGroup];
            [pendingDeleteOperation linearDependencies:self.cloudkitDeleteZoneOperations];
        }
        return pendingDeleteOperation;
    }
}

- (CKKSResultOperation*)resetCloudKitZone:(CKOperationGroup*)operationGroup {
    [self.accountStateKnown wait:(SecCKKSTestsEnabled() ? 1*NSEC_PER_SEC : 10*NSEC_PER_SEC)];

    // Not overly thread-safe, but a single read is okay
    if(self.accountStatus != CKKSAccountStatusAvailable) {
        // No CK account? goodbye!
        ckksnotice("ckksreset", self, "Requesting reset of CK zone, but no CK account exists");
        CKKSResultOperation* errorOp = [CKKSResultOperation named:@"fail" withBlockTakingSelf:^(CKKSResultOperation * _Nonnull op) {
            op.error = [NSError errorWithDomain:CKKSErrorDomain
                                          code:CKKSNotLoggedIn
                                   description:@"User is not signed into iCloud."];
        }];

        [self scheduleOperationWithoutDependencies:errorOp];
        return errorOp;
    }

    // Actually running the delete operation will be handled by the CKKS key state machine
    ckksnotice("ckksreset", self, "Requesting reset of CK zone (logged in)");
    
    __block CKKSResultOperation* deleteOperation = nil;
    [self dispatchSyncWithAccountKeys:^bool {
        self.keyStateCloudKitDeleteRequested = true;
        deleteOperation = [self createPendingDeleteZoneOperation:operationGroup];
        [self _onqueueAdvanceKeyStateMachineToState:nil withError:nil];
        return true;
    }];

    WEAKIFY(self);
    CKKSGroupOperation* viewReset = [CKKSGroupOperation named:[NSString stringWithFormat:@"cloudkit-view-reset-%@", self.zoneName]
                                          withBlockTakingSelf:^(CKKSGroupOperation *strongOp) {
        STRONGIFY(self);
        // Now that the delete finished, wait for the key hierarchy state machine
        ckksnotice("ckksreset", self, "waiting for key hierarchy to become nontransient (after cloudkit reset)");
        CKKSResultOperation* waitOp = [CKKSResultOperation named:@"waiting-for-reset" withBlock:^{}];
        [waitOp timeout: 60*NSEC_PER_SEC];
        [waitOp addNullableDependency:self.keyStateNonTransientDependency];

        [strongOp runBeforeGroupFinished:waitOp];
    }];

    [viewReset timeout:30*NSEC_PER_SEC];
    [viewReset addDependency:deleteOperation];
    [self.waitingQueue addOperation:viewReset];

    return viewReset;
}

- (void)_onqueueKeyStateMachineRequestFetch {
    dispatch_assert_queue(self.queue);

    // We're going to set this flag, then nudge the key state machine.
    // If it was idle, then it should launch a fetch. If there was an active process, this flag will stay high
    // and the fetch will be launched later.

    self.keyStateFetchRequested = true;
    [self _onqueueAdvanceKeyStateMachineToState: nil withError: nil];
}

- (void)keyStateMachineRequestProcess {
    // Since bools are atomic, we don't need to get on-queue here
    // Just set the flag high and hope
    self.keyStateProcessRequested = true;
    [self.pokeKeyStateMachineScheduler trigger];
}

- (void)_onqueueKeyStateMachineRequestProcess {
    dispatch_assert_queue(self.queue);

    // Set the request flag, then nudge the key state machine.
    // If it was idle, then it should launch a process. If there was an active process, this flag will stay high
    // and the process will be launched later.

    self.keyStateProcessRequested = true;
    [self _onqueueAdvanceKeyStateMachineToState: nil withError: nil];
}

- (CKKSResultOperation*)createKeyStateReadyDependency:(NSString*)message ckoperationGroup:(CKOperationGroup*)group {
    WEAKIFY(self);
    CKKSResultOperation* keyStateReadyDependency = [CKKSResultOperation operationWithBlock:^{
        STRONGIFY(self);
        if(!self) {
            return;
        }
        ckksnotice("ckkskey", self, "%@", message);

        [self dispatchSync:^bool {
            if(self.droppedItems) {
                // While we weren't in 'ready', keychain modifications might have come in and were dropped on the floor. Find them!
                ckksnotice("ckkskey", self, "Launching scan operation for missed items");
                [self scanLocalItems:@"ready-again-scan" ckoperationGroup:group after:nil];
            }
            return true;
        }];
    }];
    keyStateReadyDependency.name = [NSString stringWithFormat: @"%@-key-state-ready", self.zoneName];
    keyStateReadyDependency.descriptionErrorCode = CKKSResultDescriptionPendingKeyReady;
    return keyStateReadyDependency;
}

- (CKKSResultOperation*)createKeyStateNontransientDependency {
    WEAKIFY(self);
    return [CKKSResultOperation named:[NSString stringWithFormat: @"%@-key-state-nontransient", self.zoneName] withBlock:^{
        STRONGIFY(self);
        ckksnotice("ckkskey", self, "Key state is now non-transient");
    }];
}

// The operations suggested by this state machine should call _onqueueAdvanceKeyStateMachineToState once they are complete.
// At no other time should keyHierarchyState be modified.

// Note that this function cannot rely on doing any database work; it might get rolled back, especially in an error state
- (void)_onqueueAdvanceKeyStateMachineToState: (CKKSZoneKeyState*) state withError: (NSError*) error {
    dispatch_assert_queue(self.queue);
    WEAKIFY(self);

    // Resetting back to 'loggedout' takes all precedence.
    if([state isEqual:SecCKKSZoneKeyStateLoggedOut]) {
        ckksnotice("ckkskey", self, "Resetting the key hierarchy state machine back to '%@'", state);

        [self _onqueueResetSetup:SecCKKSZoneKeyStateLoggedOut
                    resetMessage:@"Key state has become ready for the first time (after reset)."
                ckoperationGroup:[CKOperationGroup CKKSGroupWithName:@"key-state-after-logout"]];

        [self _onqueueHandleKeyStateNonTransientDependency:nil];
        self.launch = nil;
        return;
    }

    [self.launch addEvent:state];

    // Resetting back to 'initialized' also takes precedence
    if([state isEqual:SecCKKSZoneKeyStateInitializing]) {
        ckksnotice("ckkskey", self, "Resetting the key hierarchy state machine back to '%@'", state);

        [self _onqueueResetSetup:SecCKKSZoneKeyStateInitializing
                    resetMessage:@"Key state has become ready for the first time (after re-initializing)."
                ckoperationGroup:[CKOperationGroup CKKSGroupWithName:@"key-state-reset-to-initializing"]];

        // Begin initialization, but rate-limit it
        self.keyStateMachineOperation = [self createPendingInitializationOperation];
        [self.keyStateMachineOperation addNullableDependency:self.zoneModifier.cloudkitRetryAfter.operationDependency];
        [self.zoneModifier.cloudkitRetryAfter trigger];
        [self scheduleOperation:self.keyStateMachineOperation];

        [self _onqueueHandleKeyStateNonTransientDependency:nil];
        return;
    }

    // Resetting to 'waitfortrust' also takes precedence
    if([state isEqualToString:SecCKKSZoneKeyStateWaitForTrust]) {
        if([self.keyHierarchyState isEqualToString:SecCKKSZoneKeyStateLoggedOut]) {
            ckksnotice("ckks", self, "Asked to waitfortrust, but we're already in loggedout. Ignoring...");
            return;
        }

        ckksnotice("ckks", self, "Entering waitfortrust");
        self.keyHierarchyState = SecCKKSZoneKeyStateWaitForTrust;
        self.keyHierarchyError = nil;
        self.keyStateMachineOperation = nil;

        [self ensureKeyStateReadyDependency:@"Key state has become ready for the first time (after lacking trust)."];

        if(self.trustStatus == CKKSAccountStatusAvailable) {
            // Note: we go to initialized here, since to enter waitfortrust CKKS has already gone through initializing
            // initialized should refetch only if needed.
            ckksnotice("ckks", self, "CKKS is trusted, moving to initialized");
            self.keyStateMachineOperation = [self operationToEnterState:SecCKKSZoneKeyStateInitialized
                                                          keyStateError:nil
                                                                  named:@"re-enter initialized"];
            [self scheduleOperation:self.keyStateMachineOperation];
        }

        // In wait for trust, we might have a keyset. Who knows!
        CKKSCurrentKeySet* keyset = [CKKSCurrentKeySet loadForZone:self.zoneID];
        [self _onqueueHandleKeyStateNonTransientDependency:keyset];

        return;
    }

    // Cancels and error states take precedence
    if([self.keyHierarchyState isEqualToString: SecCKKSZoneKeyStateError] ||
       [self.keyHierarchyState isEqualToString: SecCKKSZoneKeyStateCancelled] ||
       self.keyHierarchyError != nil) {
        // Error state: nowhere to go. Early-exit.
        ckkserror("ckkskey", self, "Asked to advance state machine from non-exit state %@ (to %@): %@", self.keyHierarchyState, state, self.keyHierarchyError);
        return;
    }

    if([state isEqual: SecCKKSZoneKeyStateError]) {
        // But wait! Is this a "we're locked" error?
        if(error && [self.lockStateTracker isLockedError:error]) {
            ckkserror("ckkskey", self, "advised of 'keychain locked' error, ignoring: coming from state (%@): %@", self.keyHierarchyState, error);
            // After the next unlock, fake that we received the last zone transition
            CKKSZoneKeyState* lastState = self.keyHierarchyState;
            self.keyStateMachineOperation = [NSBlockOperation named:@"key-state-after-unlock" withBlock:^{
                STRONGIFY(self);
                if(!self) {
                    return;
                }
                [self dispatchSyncWithAccountKeys:^bool{
                    [self _onqueueAdvanceKeyStateMachineToState:lastState withError:nil];
                    return true;
                }];
            }];
            state = nil;

            self.keyHierarchyState = SecCKKSZoneKeyStateWaitForUnlock;

            [self.keyStateMachineOperation addNullableDependency:self.lockStateTracker.unlockDependency];
            [self scheduleOperation:self.keyStateMachineOperation];

            [self _onqueueHandleKeyStateNonTransientDependency:nil];
            return;

        } else {
            // Error state: record the error and exit early
            ckkserror("ckkskey", self, "advised of error: coming from state (%@): %@", self.keyHierarchyState, error);

            [[CKKSAnalytics logger] logUnrecoverableError:error
                                                 forEvent:CKKSEventStateError
                                                   inView:self
                                           withAttributes:@{ @"previousKeyHierarchyState" : self.keyHierarchyState }];


            self.keyHierarchyState = SecCKKSZoneKeyStateError;
            self.keyHierarchyError = error;

            [self _onqueueHandleKeyStateNonTransientDependency:nil];
            return;
        }
    }

    if([state isEqual: SecCKKSZoneKeyStateCancelled]) {
        ckkserror("ckkskey", self, "advised of cancel: coming from state (%@): %@", self.keyHierarchyState, error);
        self.keyHierarchyState = SecCKKSZoneKeyStateCancelled;
        self.keyHierarchyError = error;

        // Cancel the key ready dependency. Strictly Speaking, this will cause errors down the line, but we're in a cancel state: those operations should be canceled anyway.
        self.keyHierarchyOperationGroup = nil;
        [self.keyStateReadyDependency cancel];
        self.keyStateReadyDependency = nil;

        [self.keyStateNonTransientDependency cancel];
        self.keyStateNonTransientDependency = nil;
        return;
    }

    // Now that the current or new state isn't an error or a cancel, proceed.
    if(self.keyStateMachineOperation && ![self.keyStateMachineOperation isFinished]) {
        if(state == nil) {
            // we started this operation to move the state machine. Since you aren't asking for a state transition, and there's an active operation, no need to do anything
            ckksnotice("ckkskey", self, "Not advancing state machine: waiting for %@", self.keyStateMachineOperation);
            return;
        }
    }

    if(state) {
        ckksnotice("ckkskey", self, "Preparing to advance key hierarchy state machine from %@ to %@", self.keyHierarchyState, state);
        self.keyStateMachineOperation = nil;
    } else {
        ckksnotice("ckkskey", self, "Key hierarchy state machine is being poked; currently %@", self.keyHierarchyState);
        state = self.keyHierarchyState;
    }

#if DEBUG
    // During testing, keep the developer honest: this function should always have the self identities, unless the account has lost trust
    if(self.trustStatus == CKKSAccountStatusAvailable && ![state isEqualToString:SecCKKSZoneKeyStateLoggedOut]) {
        bool hasSelfIdentities = false;
        NSAssert(self.currentTrustStates.count > 0, @"Should have at least one trust state");
        for(CKKSPeerProviderState* state in self.currentTrustStates) {
            if(state.currentSelfPeersError == nil || state.currentSelfPeersError.code != CKKSNoPeersAvailable) {
                hasSelfIdentities = true;
            }
        }

        NSAssert(hasSelfIdentities, @"Must have viable (or errored) self peers to advance key state");
    }
#endif

    // Do any of these state transitions below want to change which state we're in?
    CKKSZoneKeyState* nextState = nil;
    NSError* nextError = nil;

    // Any state that wants should fill this in; it'll be used at the end of this function as well
    CKKSCurrentKeySet* keyset = nil;

#if !defined(NDEBUG)
    {
        NSError* localerror = nil;
        NSError* allKeysError = nil;
        NSArray<CKKSKey*>* allKeys = [CKKSKey allKeys:self.zoneID error:&allKeysError];

        if(localerror) {
            ckkserror("ckkskey", self, "couldn't fetch all keys from local database, entering error state: %@", allKeysError);
        }
        ckksdebug("ckkskey", self, "All keys: %@", allKeys);
    }
#endif

    NSError* hierarchyError = nil;

    if(self.keyStateCloudKitDeleteRequested || [state isEqualToString:SecCKKSZoneKeyStateResettingZone]) {
        // CloudKit reset requests take precedence over all other state transitions
        ckksnotice("ckkskey", self, "Deleting the CloudKit Zone");
        CKKSGroupOperation* op = [[CKKSGroupOperation alloc] init];

        CKKSResultOperation* deleteOp = [self createPendingDeleteZoneOperation:self.keyHierarchyOperationGroup];
        [op runBeforeGroupFinished: deleteOp];

        NSOperation* nextStateOp = [CKKSResultOperation named:@"inspect-zone-delete" withBlockTakingSelf:^(CKKSResultOperation * _Nonnull op) {
            STRONGIFY(self);
            [self dispatchSyncWithAccountKeys:^bool {
                // Did the delete op succeed?
                if(deleteOp.error == nil) {
                    ckksnotice("ckkskey", self, "Zone deletion operation complete! Proceeding to reset local data");
                    [self _onqueueAdvanceKeyStateMachineToState:SecCKKSZoneKeyStateResettingLocalData withError:nil];
                    return true;
                }

                ckksnotice("ckkskey", self, "Zone deletion operation failed, will retry: %@", deleteOp.error);
                [self _onqueueAdvanceKeyStateMachineToState:SecCKKSZoneKeyStateResettingZone withError:nil];

                return true;
            }];
        }];

        [nextStateOp addDependency:deleteOp];
        [op runBeforeGroupFinished:nextStateOp];

        self.keyStateMachineOperation = op;
        self.keyStateCloudKitDeleteRequested = false;

        // Also, pending operations should be cancelled
        [self cancelPendingOperations];

    } else if(self.keyStateLocalResetRequested || [state isEqualToString:SecCKKSZoneKeyStateResettingLocalData]) {
        // Local reset requests take precedence over all other state transitions
        ckksnotice("ckkskey", self, "Resetting local data");
        CKKSGroupOperation* op = [[CKKSGroupOperation alloc] init];

        CKKSResultOperation* resetOp = [self createPendingResetLocalDataOperation];
        [op runBeforeGroupFinished: resetOp];

        NSOperation* nextStateOp = [self operationToEnterState:SecCKKSZoneKeyStateInitializing keyStateError:nil named:@"state-resetting-initialize"];
        [nextStateOp addDependency:resetOp];
        [op runBeforeGroupFinished:nextStateOp];

        self.keyStateMachineOperation = op;
        self.keyStateLocalResetRequested = false;

    } else if([state isEqualToString:SecCKKSZoneKeyStateZoneCreationFailed]) {
        //Prepare to go back into initializing, as soon as the cloudkitRetryAfter is happy
        self.keyStateMachineOperation = [self operationToEnterState:SecCKKSZoneKeyStateInitializing keyStateError:nil named:@"recover-from-cloudkit-failure"];
        [self.keyStateMachineOperation addNullableDependency:self.zoneModifier.cloudkitRetryAfter.operationDependency];
        [self.zoneModifier.cloudkitRetryAfter trigger];

    } else if([state isEqualToString:SecCKKSZoneKeyStateWaitForTrust]) {
        // Actually entering this state should have been handled above, so let's check if we can exit it here...
        if(self.trustStatus == CKKSAccountStatusAvailable) {
            ckksnotice("ckkskey", self, "Beginning trusted state machine operation");
            nextState = SecCKKSZoneKeyStateInitialized;

        } else if (self.tlkCreationRequested) {
            ckksnotice("ckkskey", self, "No trust, but TLK creation is requested. Moving to fetchcomplete.");
            nextState = SecCKKSZoneKeyStateFetchComplete;

        } else {
            ckksnotice("ckkskey", self, "Remaining in 'waitfortrust'");
        }

    } else if([state isEqualToString: SecCKKSZoneKeyStateReady]) {
        NSError* localerror = nil;
        NSArray<CKKSKey*>* remoteKeys = [CKKSKey remoteKeys:self.zoneID error: &localerror];

        if(remoteKeys == nil || localerror) {
            ckkserror("ckkskey", self, "couldn't fetch keys from local database, entering error state: %@", localerror);
            self.keyHierarchyState = SecCKKSZoneKeyStateError;
            self.keyHierarchyError = localerror;
            [self _onqueueHandleKeyStateNonTransientDependency:nil];
            return;
        }

        if(self.keyStateProcessRequested || [remoteKeys count] > 0) {
            // We've either received some remote keys from the last fetch, or someone has requested a reprocess.
            ckksnotice("ckkskey", self, "Kicking off a key reprocess based on request:%d and remote key count %lu", self.keyStateProcessRequested, (unsigned long)[remoteKeys count]);
            nextState = SecCKKSZoneKeyStateProcess;

        } else if(self.keyStateFullRefetchRequested) {
            // In ready, but someone has requested a full fetch. Kick it off.
            ckksnotice("ckkskey", self, "Kicking off a full key refetch based on request:%d", self.keyStateFullRefetchRequested);
            nextState = SecCKKSZoneKeyStateNeedFullRefetch;

        } else if(self.keyStateFetchRequested) {
            // In ready, but someone has requested a fetch. Kick it off.
            ckksnotice("ckkskey", self, "Kicking off a key refetch based on request:%d", self.keyStateFetchRequested);
            nextState = SecCKKSZoneKeyStateFetch; // Don't go to 'ready', go to 'initialized', since we want to fetch again
        } else if (self.trustStatus != CKKSAccountStatusAvailable) {
            ckksnotice("ckkskey", self, "Asked to go into ready, but there's no trust; going into waitfortrust");
            nextState = SecCKKSZoneKeyStateWaitForTrust;
        } else if (self.trustedPeersSetChanged) {
            ckksnotice("ckkskey", self, "Received a nudge that the trusted peers set might have changed! Reprocessing.");
            nextState = SecCKKSZoneKeyStateProcess;
            self.trustedPeersSetChanged = false;
        }

        // TODO: kick off a key roll if one has been requested

        if(!self.keyStateMachineOperation && !nextState) {
            // We think we're ready. Double check.
            keyset = [CKKSCurrentKeySet loadForZone:self.zoneID];
            CKKSZoneKeyState* checkedstate = [self _onqueueEnsureKeyHierarchyHealth:keyset error:&hierarchyError];
            if(![checkedstate isEqualToString:SecCKKSZoneKeyStateReady] || hierarchyError) {
                // Things is bad. Kick off a heal to fix things up.
                ckksnotice("ckkskey", self, "Thought we were ready, but the key hierarchy is %@: %@", checkedstate, hierarchyError);
                nextState = checkedstate;
                if([nextState isEqualToString:SecCKKSZoneKeyStateError]) {
                    nextError = hierarchyError;
                }
            }
        }

    } else if([state isEqualToString: SecCKKSZoneKeyStateInitialized]) {
        // We're initialized and CloudKit is ready. If we're trusted, see what needs done. Otherwise, wait.

        // Note: we might be still 'untrusted' at this point. The state machine is responsible for not entering 'ready' until
        // we are trusted.
        // This is acceptable only if the key state machine does not make new TLKs without being trusted!

        // Set this state, for test use
        self.keyHierarchyState = SecCKKSZoneKeyStateInitialized;

        CKKSZoneStateEntry* ckse = [CKKSZoneStateEntry state:self.zoneName];
        [self _onqueuePerformKeyStateInitialized:ckse];

        // We need to either:
        //  Wait for the fixup operation to occur
        //  Go into 'ready'
        //  Or start a key state fetch
        if(self.lastFixupOperation && ![self.lastFixupOperation isFinished]) {
            nextState = SecCKKSZoneKeyStateWaitForFixupOperation;
        } else {
            // Check if we have an existing key hierarchy in keyset
            keyset = [CKKSCurrentKeySet loadForZone:self.zoneID];
            if(keyset.error && !([keyset.error.domain isEqual: @"securityd"] && keyset.error.code == errSecItemNotFound)) {
                ckkserror("ckkskey", self, "Error examining existing key hierarchy: %@", error);
            }

            if(keyset.tlk && keyset.classA && keyset.classC && !keyset.error) {
                // This is likely a restart of securityd, and we think we're ready. Double check.

                CKKSZoneKeyState* checkedstate = [self _onqueueEnsureKeyHierarchyHealth:keyset error:&hierarchyError];
                if([checkedstate isEqualToString:SecCKKSZoneKeyStateReady] && !hierarchyError) {
                    ckksnotice("ckkskey", self, "Already have existing key hierarchy for %@; using it.", self.zoneID.zoneName);
                } else {
                    ckksnotice("ckkskey", self, "Initial scan shows key hierarchy is %@: %@", checkedstate, hierarchyError);
                }
                nextState = checkedstate;

            } else {
                // We have no local key hierarchy. One might exist in CloudKit, or it might not.
                ckksnotice("ckkskey", self, "No existing key hierarchy for %@. Check if there's one in CloudKit...", self.zoneID.zoneName);
                nextState = SecCKKSZoneKeyStateFetch;
            }
        }

    } else if([state isEqualToString:SecCKKSZoneKeyStateFetch]) {
        ckksnotice("ckkskey", self, "Starting a key hierarchy fetch");
        [self _onqueueKeyHierarchyFetch];

    } else if([state isEqualToString: SecCKKSZoneKeyStateNeedFullRefetch]) {
        ckksnotice("ckkskey", self, "Starting a key hierarchy full refetch");
        [self _onqueueKeyHierarchyFetchForReasons:[NSSet setWithObjects:CKKSFetchBecauseKeyHierarchy, CKKSFetchBecauseResync, nil]];
        self.keyStateMachineRefetched = true;
        self.keyStateFullRefetchRequested = false;

    } else if([state isEqualToString:SecCKKSZoneKeyStateWaitForFixupOperation]) {
        // We should enter 'initialized' when the fixup operation completes
        ckksnotice("ckkskey", self, "Waiting for the fixup operation: %@", self.lastFixupOperation);

        self.keyStateMachineOperation = [NSBlockOperation named:@"key-state-after-fixup" withBlock:^{
            STRONGIFY(self);
            [self dispatchSyncWithAccountKeys:^bool{
                ckksnotice("ckkskey", self, "Fixup operation complete! Restarting key hierarchy machinery");
                [self _onqueueAdvanceKeyStateMachineToState:SecCKKSZoneKeyStateInitialized withError:nil];
                return true;
            }];
        }];
        [self.keyStateMachineOperation addNullableDependency:self.lastFixupOperation];

    } else if([state isEqualToString: SecCKKSZoneKeyStateFetchComplete]) {
        // We've just completed a fetch of everything. Are there any remote keys?
        keyset = [CKKSCurrentKeySet loadForZone:self.zoneID];

        NSError* localerror = nil;

        NSArray<CKKSKey*>* localKeys = [CKKSKey localKeys:self.zoneID error:&localerror];
        NSArray<CKKSKey*>* remoteKeys = [CKKSKey remoteKeys:self.zoneID error: &localerror];

        if(localKeys == nil || remoteKeys == nil || localerror) {
            ckkserror("ckkskey", self, "couldn't fetch keys from local database, entering error state: %@", localerror);
            self.keyHierarchyState = SecCKKSZoneKeyStateError;
            self.keyHierarchyError = localerror;
            [self _onqueueHandleKeyStateNonTransientDependency:nil];
            return;
        }

        if(remoteKeys.count > 0u) {
            // Process the keys we received.
            self.keyStateMachineOperation = [[CKKSProcessReceivedKeysStateMachineOperation alloc] initWithCKKSKeychainView: self];
        } else if( (keyset.currentTLKPointer || keyset.currentClassAPointer || keyset.currentClassCPointer) &&
                  !(keyset.tlk && keyset.classA && keyset.classC)) {
            // Huh. We appear to have current key pointers, but the keys themselves don't exist. That's weird.
            // Transfer to the "unhealthy" state to request a fix
            ckksnotice("ckkskey", self, "We appear to have current key pointers but no keys to match them: %@ Moving to 'unhealthy'", keyset);
            nextState = SecCKKSZoneKeyStateUnhealthy;
        } else {
            // No remote keys, and the pointers look sane? Do we have an existing key hierarchy?
            CKKSZoneKeyState* checkedstate = [self _onqueueEnsureKeyHierarchyHealth:keyset error:&hierarchyError];
            if([checkedstate isEqualToString:SecCKKSZoneKeyStateReady] && !hierarchyError) {
                ckksnotice("ckkskey", self, "After fetch, everything looks good.");
                nextState = checkedstate;

            } else if(localKeys.count == 0 && remoteKeys.count == 0) {
                ckksnotice("ckkskey", self, "After fetch, we don't have any key hierarchy. Entering a waiting state: %@", hierarchyError ?: @"no error");
                nextState = SecCKKSZoneKeyStateWaitForTLKCreation;
            } else {
                ckksnotice("ckkskey", self, "After fetch, we have a possibly unhealthy key hierarchy. Moving to %@: %@", checkedstate, hierarchyError ?: @"no error");
                nextState = checkedstate;
            }
        }

    } else if([state isEqualToString:SecCKKSZoneKeyStateWaitForTLKCreation]) {

        if(self.tlkCreationRequested) {
            self.tlkCreationRequested = false;
            ckksnotice("ckkskey", self, "TLK creation requested; kicking off operation");
            self.keyStateMachineOperation = [[CKKSNewTLKOperation alloc] initWithCKKSKeychainView: self ckoperationGroup:self.keyHierarchyOperationGroup];

        } else if(self.keyStateProcessRequested) {
            ckksnotice("ckkskey", self, "We believe we need to create TLKs but we also received a key nudge; moving to key state Process.");
            nextState = SecCKKSZoneKeyStateProcess;

        } else {
            ckksnotice("ckkskey", self, "We believe we need to create TLKs; waiting for Octagon (via %@)", self.suggestTLKUpload);
            [self.suggestTLKUpload trigger];
        }


    } else if([state isEqualToString:SecCKKSZoneKeyStateWaitForTLKUpload]) {
        ckksnotice("ckkskey", self, "We believe we have TLKs that need uploading");


        if(self.keyStateProcessRequested) {
            keyset = [CKKSCurrentKeySet loadForZone:self.zoneID];
            if(keyset.currentTLKPointer.currentKeyUUID) {
                ckksnotice("ckkskey", self, "Received a nudge that our TLK records might be here (and there's some current TLK pointer)");
                nextState = SecCKKSZoneKeyStateProcess;
            } else {
                ckksnotice("ckkskey", self, "Received a nudge that our TLK records might be here, but there's no TLK pointer. Staying in WaitForTLKUpload.");
                self.keyStateProcessRequested = false;
            }
        }

        if(nextState == nil) {
            ckksnotice("ckkskey", self, "Alerting any listener of our proposed keyset: %@", self.lastNewTLKOperation.keyset);
            [self _onqueueRunKeysetProviderOperations:self.lastNewTLKOperation.keyset];

            ckksnotice("ckkskey", self, "Notifying Octagon again, just in case");
            [self.suggestTLKUpload trigger];
        }

    } else if([state isEqualToString: SecCKKSZoneKeyStateWaitForTLK]) {
        // We're in a hold state: waiting for the TLK bytes to arrive.

        if(self.keyStateProcessRequested) {
            // Someone has requsted a reprocess! Go to the correct state.
            ckksnotice("ckkskey", self, "Received a nudge that our TLK might be here! Reprocessing.");
            nextState = SecCKKSZoneKeyStateProcess;

        } else if(self.trustedPeersSetChanged) {
            // Hmm, maybe this trust set change will cause us to recover this TLK (due to a previously-untrusted share becoming trusted). Worth a shot!
            ckksnotice("ckkskey", self, "Received a nudge that the trusted peers set might have changed! Reprocessing.");
            nextState = SecCKKSZoneKeyStateProcess;
            self.trustedPeersSetChanged = false;

        } else {
            keyset = [CKKSCurrentKeySet loadForZone:self.zoneID];

            // Should we nuke this zone?
            if(self.trustStatus == CKKSAccountStatusAvailable) {
                if([self _onqueueOtherDevicesReportHavingTLKs:keyset]) {
                    ckksnotice("ckkskey", self, "Other devices report having TLK(%@). Entering a waiting state", keyset.currentTLKPointer);
                } else {
                    ckksnotice("ckkskey", self, "No other devices have TLK(%@). Beginning zone reset...", keyset.currentTLKPointer);
                    self.keyHierarchyOperationGroup = [CKOperationGroup CKKSGroupWithName:@"tlk-missing"];
                    nextState = SecCKKSZoneKeyStateResettingZone;
                }
            } else {
                ckksnotice("ckkskey", self, "This device isn't trusted, so don't modify the existing TLK(%@)", keyset.currentTLKPointer);
                nextState = SecCKKSZoneKeyStateWaitForTrust;
            }
        }

    } else if([state isEqualToString: SecCKKSZoneKeyStateWaitForUnlock]) {
        ckksnotice("ckkskey", self, "Requested to enter waitforunlock");
        self.keyStateMachineOperation = [self operationToEnterState:SecCKKSZoneKeyStateInitialized keyStateError:nil named:@"key-state-after-unlock"];
        [self.keyStateMachineOperation addNullableDependency: self.lockStateTracker.unlockDependency];

    } else if([state isEqualToString: SecCKKSZoneKeyStateReadyPendingUnlock]) {
        ckksnotice("ckkskey", self, "Believe we're ready, but rechecking after unlock");
        self.keyStateMachineOperation = [self operationToEnterState:SecCKKSZoneKeyStateInitialized keyStateError:nil named:@"key-state-after-unlock"];
        [self.keyStateMachineOperation addNullableDependency: self.lockStateTracker.unlockDependency];

    } else if([state isEqualToString: SecCKKSZoneKeyStateBadCurrentPointers]) {
        // The current key pointers are broken, but we're not sure why.
        ckksnotice("ckkskey", self, "Our current key pointers are reported broken. Attempting a fix!");
        self.keyStateMachineOperation = [[CKKSHealKeyHierarchyOperation alloc] initWithCKKSKeychainView: self ckoperationGroup:self.keyHierarchyOperationGroup];

    } else if([state isEqualToString: SecCKKSZoneKeyStateNewTLKsFailed]) {
        ckksnotice("ckkskey", self, "Creating new TLKs didn't work. Attempting to refetch!");
        [self _onqueueKeyHierarchyFetch];

    } else if([state isEqualToString: SecCKKSZoneKeyStateHealTLKSharesFailed]) {
        ckksnotice("ckkskey", self, "Creating new TLK shares didn't work. Attempting to refetch!");
        [self _onqueueKeyHierarchyFetch];

    } else if([state isEqualToString:SecCKKSZoneKeyStateUnhealthy]) {
        if(self.trustStatus != CKKSAccountStatusAvailable) {
            ckksnotice("ckkskey", self, "Looks like the key hierarchy is unhealthy, but we're untrusted.");
            nextState = SecCKKSZoneKeyStateWaitForTrust;

        } else {
            ckksnotice("ckkskey", self, "Looks like the key hierarchy is unhealthy. Launching fix.");
            self.keyStateMachineOperation = [[CKKSHealKeyHierarchyOperation alloc] initWithCKKSKeychainView:self ckoperationGroup:self.keyHierarchyOperationGroup];
        }

    } else if([state isEqualToString:SecCKKSZoneKeyStateHealTLKShares]) {
        ckksnotice("ckksshare", self, "Key hierarchy is okay, but not shared appropriately. Launching fix.");
        self.keyStateMachineOperation = [[CKKSHealTLKSharesOperation alloc] initWithCKKSKeychainView:self
                                                                                    ckoperationGroup:self.keyHierarchyOperationGroup];

    } else if([state isEqualToString:SecCKKSZoneKeyStateProcess]) {
        ckksnotice("ckksshare", self, "Launching key state process");
        self.keyStateMachineOperation = [[CKKSProcessReceivedKeysStateMachineOperation alloc] initWithCKKSKeychainView: self];

        // Since we're starting a reprocess, this is answering all previous requests.
        self.keyStateProcessRequested = false;

    } else {
        ckkserror("ckks", self, "asked to advance state machine to unknown state: %@", state);
        self.keyHierarchyState = state;

        keyset = [CKKSCurrentKeySet loadForZone:self.zoneID];
        [self _onqueueHandleKeyStateNonTransientDependency:keyset];
        return;
    }

    // Handle the key state ready dependency
    // If we're in ready and not entering a non-ready state, we should activate the ready dependency. Otherwise, we should create it.
    if(([state isEqualToString:SecCKKSZoneKeyStateReady] || [state isEqualToString:SecCKKSZoneKeyStateReadyPendingUnlock]) &&
       (nextState == nil || [nextState isEqualToString:SecCKKSZoneKeyStateReady] || [nextState isEqualToString:SecCKKSZoneKeyStateReadyPendingUnlock])) {

        // Ready enough!
        [[CKKSAnalytics logger] setDateProperty:[NSDate date] forKey:CKKSAnalyticsLastKeystateReady inView:self];

        if(self.keyStateReadyDependency) {
            [self scheduleOperation: self.keyStateReadyDependency];
            self.keyStateReadyDependency = nil;
        }

        // If there are any OQEs waiting to be encrypted, launch an op to fix them
        NSError* localerror = nil;
        NSInteger outdatedOQEs = [CKKSOutgoingQueueEntry countByState:SecCKKSStateReencrypt zone:self.zoneID error:&localerror];

        if(localerror) {
           ckkserror("ckkskey", self, "couldn't fetch OQEs from local database, entering error state: %@", localerror);
            self.keyHierarchyState = SecCKKSZoneKeyStateError;
            self.keyHierarchyError = localerror;
            [self _onqueueHandleKeyStateNonTransientDependency:nil];
            return;
        }

        if(outdatedOQEs > 0) {
            ckksnotice("ckksreencrypt", self, "Reencrypting outgoing items as the key hierarchy is ready");
            CKKSReencryptOutgoingItemsOperation* op = [[CKKSReencryptOutgoingItemsOperation alloc] initWithCKKSKeychainView:self ckoperationGroup:self.keyHierarchyOperationGroup];
            [self scheduleOperation:op];
        }
    } else {
        // Not in ready: we need a key state ready dependency
        if(self.keyStateReadyDependency == nil || [self.keyStateReadyDependency isFinished]) {
            self.keyHierarchyOperationGroup = [CKOperationGroup CKKSGroupWithName:@"key-state-broken"];
            self.keyStateReadyDependency = [self createKeyStateReadyDependency:@"Key state has become ready again." ckoperationGroup:self.keyHierarchyOperationGroup];
        }
    }

    NSAssert(!((self.keyStateMachineOperation != nil) &&
               (nextState != nil)),
             @"Should have a machine operation or a next state, not both");

    // Start any operations, or log that we aren't
    if(self.keyStateMachineOperation) {
        [self scheduleOperation: self.keyStateMachineOperation];
        ckksnotice("ckkskey", self, "Now in key state: %@", state);
        self.keyHierarchyState = state;

    } else if([state isEqualToString:SecCKKSZoneKeyStateError]) {
        ckksnotice("ckkskey", self, "Entering key state 'error'");
        self.keyHierarchyState = state;

    } else if(nextState == nil) {
        ckksnotice("ckkskey", self, "Entering key state: %@", state);
        self.keyHierarchyState = state;

    } else if(![state isEqualToString: nextState]) {
        ckksnotice("ckkskey", self, "Staying in state %@, but proceeding to %@ as soon as possible", self.keyHierarchyState, nextState);
        self.keyStateMachineOperation = [self operationToEnterState:nextState keyStateError:nextError named:[NSString stringWithFormat:@"next-key-state-%@", nextState]];
        [self scheduleOperation: self.keyStateMachineOperation];

    } else {
        // Nothing to do and not in a waiting state? This is likely a bug, but, hey: pretend to be in ready!
        if(!([state isEqualToString:SecCKKSZoneKeyStateReady] || [state isEqualToString:SecCKKSZoneKeyStateReadyPendingUnlock])) {
            ckkserror("ckkskey", self, "No action to take in state %@; BUG, but: maybe we're ready?", state);
            nextState = SecCKKSZoneKeyStateReady;
            self.keyStateMachineOperation = [self operationToEnterState:nextState keyStateError:nil named:@"next-key-state"];
            [self scheduleOperation: self.keyStateMachineOperation];
        }
    }

    // If the keystate is non-transient, ensure we've loaded the keyset, and provide it to any waiters
    // If it is transient, just call the handler anyway: it needs to set up the dependency
    if(!CKKSKeyStateTransient(self.keyHierarchyState) && keyset == nil) {
        keyset = [CKKSCurrentKeySet loadForZone:self.zoneID];
    }
    [self _onqueueHandleKeyStateNonTransientDependency:keyset];
}

- (void)_onqueueHandleKeyStateNonTransientDependency:(CKKSCurrentKeySet* _Nullable)keyset {
    dispatch_assert_queue(self.queue);

    if(CKKSKeyStateTransient(self.keyHierarchyState)) {
        if(self.keyStateNonTransientDependency == nil || [self.keyStateNonTransientDependency isFinished]) {
            self.keyStateNonTransientDependency = [self createKeyStateNontransientDependency];
        }
    } else {
        // Nontransient: go for it
        if(self.keyStateNonTransientDependency) {
            [self scheduleOperation: self.keyStateNonTransientDependency];
            self.keyStateNonTransientDependency = nil;
        }

        if(keyset && keyset.currentTLKPointer.currentKeyUUID) {
            [self _onqueueRunKeysetProviderOperations:keyset];
        } else {
            ckksnotice("ckkskey", self, "State machine is nontransient, but no keyset...");
        }
    }
}

- (NSOperation*)operationToEnterState:(CKKSZoneKeyState*)state keyStateError:(NSError* _Nullable)keyStateError named:(NSString*)name {
    WEAKIFY(self);

    return [NSBlockOperation named:name withBlock:^{
        STRONGIFY(self);
        if(!self) {
            return;
        }
        [self dispatchSyncWithAccountKeys:^bool{
            [self _onqueueAdvanceKeyStateMachineToState:state withError:keyStateError];
            return true;
        }];
    }];
}

- (BOOL)otherDevicesReportHavingTLKs:(CKKSCurrentKeySet*)keyset
{
    __block BOOL report = false;
    [self dispatchSync:^bool{
        report = [self _onqueueOtherDevicesReportHavingTLKs:keyset];
        return true;
    }];
    return report ? YES : NO;
}

- (bool)_onqueueOtherDevicesReportHavingTLKs:(CKKSCurrentKeySet*)keyset
{
    dispatch_assert_queue(self.queue);

    //Has there been any activity indicating that other trusted devices have keys in the past 45 days, or untrusted devices in the past 4?
    // (We chose 4 as devices attempt to upload their device state every 3 days. If a device is unceremoniously kicked out of circle, we normally won't immediately reset.)
    NSDate* now = [NSDate date];
    NSDateComponents* trustedOffset = [[NSDateComponents alloc] init];
    [trustedOffset setDay:-45];
    NSDate* trustedDeadline = [[NSCalendar currentCalendar] dateByAddingComponents:trustedOffset toDate:now options:0];

    NSDateComponents* untrustedOffset = [[NSDateComponents alloc] init];
    [untrustedOffset setDay:-4];
    NSDate* untrustedDeadline = [[NSCalendar currentCalendar] dateByAddingComponents:untrustedOffset toDate:now options:0];


    NSMutableSet<NSString*>* trustedPeerIDs = [NSMutableSet set];
    for(CKKSPeerProviderState* trustState in self.currentTrustStates) {
        for(id<CKKSPeer> peer in trustState.currentTrustedPeers) {
            [trustedPeerIDs addObject:peer.peerID];
        }
    }

    NSError* localerror = nil;

    NSArray<CKKSDeviceStateEntry*>* allDeviceStates = [CKKSDeviceStateEntry allInZone:self.zoneID error:&localerror];
    if(localerror) {
        ckkserror("ckkskey", self, "Error fetching device states: %@", localerror);
        localerror = nil;
        return true;
    }
    for(CKKSDeviceStateEntry* device in allDeviceStates) {
        // The peerIDs in CDSEs aren't written with the peer prefix. Make sure we match both.
        NSString* sosPeerID = device.circlePeerID ? [CKKSSOSPeerPrefix stringByAppendingString:device.circlePeerID] : nil;

        if([trustedPeerIDs containsObject:device.circlePeerID] ||
           [trustedPeerIDs containsObject:sosPeerID] ||
           [trustedPeerIDs containsObject:device.octagonPeerID]) {
            // Is this a recent DSE? If it's older than the deadline, skip it
            if([device.storedCKRecord.modificationDate compare:trustedDeadline] == NSOrderedAscending) {
                ckksnotice("ckkskey", self, "Trusted device state (%@) is too old; ignoring", device);
                continue;
            }
        } else {
            // Device is untrusted. How does it fare with the untrustedDeadline?
            if([device.storedCKRecord.modificationDate compare:untrustedDeadline] == NSOrderedAscending) {
                ckksnotice("ckkskey", self, "Device (%@) is not trusted and from too long ago; ignoring device state (%@)", device.circlePeerID, device);
                continue;
            } else {
                ckksnotice("ckkskey", self, "Device (%@) is not trusted, but very recent. Including in heuristic: %@", device.circlePeerID, device);
            }
        }

        if([device.keyState isEqualToString:SecCKKSZoneKeyStateReady] ||
           [device.keyState isEqualToString:SecCKKSZoneKeyStateReadyPendingUnlock]) {
            ckksnotice("ckkskey", self, "Other device (%@) has keys; it should send them to us", device);
            return true;
        }
    }

    NSArray<CKKSTLKShareRecord*>* tlkShares = [CKKSTLKShareRecord allForUUID:keyset.currentTLKPointer.currentKeyUUID
                                                          zoneID:self.zoneID
                                                           error:&localerror];
    if(localerror) {
        ckkserror("ckkskey", self, "Error fetching device states: %@", localerror);
        localerror = nil;
        return false;
    }

    for(CKKSTLKShareRecord* tlkShare in tlkShares) {
        if([trustedPeerIDs containsObject:tlkShare.senderPeerID] &&
           [tlkShare.storedCKRecord.modificationDate compare:trustedDeadline] == NSOrderedDescending) {
            ckksnotice("ckkskey", self, "Trusted TLK Share (%@) created recently; other devices have keys and should send them to us", tlkShare);
            return true;
        }
    }

    // Okay, how about the untrusted deadline?
    for(CKKSTLKShareRecord* tlkShare in tlkShares) {
        if([tlkShare.storedCKRecord.modificationDate compare:untrustedDeadline] == NSOrderedDescending) {
            ckksnotice("ckkskey", self, "Untrusted TLK Share (%@) created very recently; other devices might have keys and should rejoin the circle (and send them to us)", tlkShare);
            return true;
        }
    }

    return false;
}

// For this key, who doesn't yet have a valid CKKSTLKShare for it?
// Note that we really want a record sharing the TLK to ourselves, so this function might return
// a non-empty set even if all peers have the TLK: it wants us to make a record for ourself.
- (NSSet<id<CKKSPeer>>*)_onqueueFindPeers:(CKKSPeerProviderState*)trustState
                             missingShare:(CKKSKey*)key
                           afterUploading:(NSSet<CKKSTLKShareRecord*>* _Nullable)newShares
                                    error:(NSError* __autoreleasing*)error
{
    dispatch_assert_queue(self.queue);

    if(!key) {
        ckkserror("ckksshare", self, "Attempting to find missing shares for nil key");
        return [NSSet set];
    }

    if(trustState.currentTrustedPeersError) {
        ckkserror("ckksshare", self, "Couldn't find missing shares because trusted peers aren't available: %@", trustState.currentTrustedPeersError);
        if(error) {
            *error = trustState.currentTrustedPeersError;
        }
        return [NSSet set];
    }
    if(trustState.currentSelfPeersError) {
        ckkserror("ckksshare", self, "Couldn't find missing shares because self peers aren't available: %@", trustState.currentSelfPeersError);
        if(error) {
            *error = trustState.currentSelfPeersError;
        }
        return [NSSet set];
    }

    NSMutableSet<id<CKKSPeer>>* peersMissingShares = [NSMutableSet set];

    // Ensure that the 'self peer' is one of the current trusted peers. Otherwise, any TLKShare we create
    // won't be considered trusted the next time through...
    if(![trustState.currentTrustedPeerIDs containsObject:trustState.currentSelfPeers.currentSelf.peerID]) {
        ckkserror("ckksshare", self, "current self peer (%@) is not in the set of trusted peers: %@",
                  trustState.currentSelfPeers.currentSelf.peerID,
                  trustState.currentTrustedPeerIDs);

        if(error) {
            *error = [NSError errorWithDomain:CKKSErrorDomain
                                         code:CKKSLackingTrust
                                  description:[NSString stringWithFormat:@"current self peer (%@) is not in the set of trusted peers",
                                               trustState.currentSelfPeers.currentSelf.peerID]];
        }

        return nil;
    }

    for(id<CKKSRemotePeerProtocol> peer in trustState.currentTrustedPeers) {
        if(![peer shouldHaveView:self.zoneName]) {
            ckkserror("ckksshare", self, "Peer (%@) is not supposed to have view, skipping", peer);
            continue;
        }

        NSError* peerError = nil;
        // Find all the shares for this peer for this key
        NSArray<CKKSTLKShareRecord*>* currentPeerShares = [CKKSTLKShareRecord allFor:peer.peerID
                                                                 keyUUID:key.uuid
                                                                  zoneID:self.zoneID
                                                                   error:&peerError];

        if(peerError) {
            ckkserror("ckksshare", self, "Couldn't load shares for peer %@: %@", peer, peerError);
            if(error) {
                *error = peerError;
            }
            return nil;
        }

        // Include the new shares, too....
        NSArray<CKKSTLKShareRecord*>* possiblePeerShares = newShares ? [currentPeerShares arrayByAddingObjectsFromArray:[newShares allObjects]] : currentPeerShares;

        // Determine if we think this peer has enough things shared to them
        bool alreadyShared = false;
        for(CKKSTLKShareRecord* existingPeerShare in possiblePeerShares) {
            // Ensure this share is to this peer...
            if(![existingPeerShare.share.receiverPeerID isEqualToString:peer.peerID]) {
                continue;
            }

            // If an SOS Peer sent this share, is its signature still valid? Or did the signing key change?
            if([existingPeerShare.senderPeerID hasPrefix:CKKSSOSPeerPrefix]) {
                NSError* signatureError = nil;
                if(![existingPeerShare signatureVerifiesWithPeerSet:trustState.currentTrustedPeers error:&signatureError]) {
                    ckksnotice("ckksshare", self, "Existing TLKShare's signature doesn't verify with current peer set: %@ %@", signatureError, existingPeerShare);
                    continue;
                }
            }

            if([existingPeerShare.tlkUUID isEqualToString:key.uuid] && [trustState.currentTrustedPeerIDs containsObject:existingPeerShare.senderPeerID]) {
                // Was this shared to us?
                if([peer.peerID isEqualToString: trustState.currentSelfPeers.currentSelf.peerID]) {
                    // We only count this as 'found' if we did the sharing and it's to our current keys
                    NSData* currentKey = trustState.currentSelfPeers.currentSelf.publicEncryptionKey.keyData;

                    if([existingPeerShare.senderPeerID isEqualToString:trustState.currentSelfPeers.currentSelf.peerID] &&
                       [existingPeerShare.share.receiverPublicEncryptionKeySPKI isEqual:currentKey]) {
                        ckksnotice("ckksshare", self, "Local peer %@ is shared %@ via self: %@", peer, key, existingPeerShare);
                        alreadyShared = true;
                        break;
                    } else {
                        ckksnotice("ckksshare", self, "Local peer %@ is shared %@ via trusted %@, but that's not good enough", peer, key, existingPeerShare);
                    }

                } else {
                    // Was this shared to the remote peer's current keys?
                    NSData* currentKeySPKI = peer.publicEncryptionKey.keyData;

                    if([existingPeerShare.share.receiverPublicEncryptionKeySPKI isEqual:currentKeySPKI]) {
                        // Some other peer has a trusted share. Cool!
                        ckksnotice("ckksshare", self, "Peer %@ is shared %@ via trusted %@", peer, key, existingPeerShare);
                        alreadyShared = true;
                        break;
                    } else {
                        ckksnotice("ckksshare", self, "Peer %@ has a share for %@, but to old keys: %@", peer, key, existingPeerShare);
                    }
                }
            }
        }

        if(!alreadyShared) {
            // Add this peer to our set, if it has an encryption key to receive the share
            if(peer.publicEncryptionKey) {
                [peersMissingShares addObject:peer];
            }
        }
    }

    if(peersMissingShares.count > 0u) {
        // Log each and every one of the things
        ckksnotice("ckksshare", self, "Missing TLK shares for %lu peers: %@", (unsigned long)peersMissingShares.count, peersMissingShares);
        ckksnotice("ckksshare", self, "Self peers are (%@) %@", trustState.currentSelfPeersError ?: @"no error", trustState.currentSelfPeers);
        ckksnotice("ckksshare", self, "Trusted peers are (%@) %@", trustState.currentTrustedPeersError ?: @"no error", trustState.currentTrustedPeers);
    }

    return peersMissingShares;
}

- (BOOL)_onqueueAreNewSharesSufficient:(NSSet<CKKSTLKShareRecord*>*)newShares
                            currentTLK:(CKKSKey*)key
                                 error:(NSError* __autoreleasing*)error
{
    dispatch_assert_queue(self.queue);

    for(CKKSPeerProviderState* trustState in self.currentTrustStates) {
        NSError* localError = nil;
        NSSet<id<CKKSPeer>>* peersMissingShares = [self _onqueueFindPeers:trustState
                                                             missingShare:key
                                                           afterUploading:newShares
                                                                    error:&localError];
        if(peersMissingShares == nil || localError) {
            if(trustState.essential) {
                if(error) {
                    *error = localError;
                }
                return NO;
            } else {
                ckksnotice("ckksshare", self, "Failed to find peers for nonessential system: %@", trustState);
                // Not a hard failure.
            }
        }

        if(peersMissingShares.count > 0) {
            ckksnotice("ckksshare", self, "New share set is missing shares for peers: %@", peersMissingShares);
            return NO;
        }
    }

    return YES;
}

- (NSSet<CKKSTLKShareRecord*>*)_onqueueCreateMissingKeyShares:(CKKSKey*)key
                                                        error:(NSError* __autoreleasing*)error
{
    NSError* localerror = nil;
    NSSet<CKKSTLKShareRecord*>* newShares = nil;

    // If any one of our trust states succeed, this function doesn't have an error
    for(CKKSPeerProviderState* trustState in self.currentTrustStates) {
        NSError* stateError = nil;

        NSSet<CKKSTLKShareRecord*>* newTrustShares = [self _onqueueCreateMissingKeyShares:key
                                                                                    peers:trustState
                                                                                    error:&stateError];


        if(newTrustShares && !stateError) {
            newShares = newShares ? [newShares setByAddingObjectsFromSet:newTrustShares] : newTrustShares;
        } else {
            ckksnotice("ckksshare", self, "Unable to create shares for trust set %@: %@", trustState, stateError);
            if(localerror == nil) {
                localerror = stateError;
            }
        }
    }

    // Only report an error if none of the trust states were able to succeed
    if(newShares) {
        return newShares;
    } else {
        if(error && localerror) {
            *error = localerror;
        }
        return nil;
    }
}

- (NSSet<CKKSTLKShareRecord*>*)_onqueueCreateMissingKeyShares:(CKKSKey*)key
                                                        peers:(CKKSPeerProviderState*)trustState
                                                        error:(NSError* __autoreleasing*)error
{
    dispatch_assert_queue(self.queue);

    if(trustState.currentTrustedPeersError) {
        ckkserror("ckksshare", self, "Couldn't create missing shares because trusted peers aren't available: %@", trustState.currentTrustedPeersError);
        if(error) {
            *error = trustState.currentTrustedPeersError;
        }
        return nil;
    }
    if(trustState.currentSelfPeersError) {
        ckkserror("ckksshare", self, "Couldn't create missing shares because self peers aren't available: %@", trustState.currentSelfPeersError);
        if(error) {
            *error = trustState.currentSelfPeersError;
        }
        return nil;
    }

    NSSet<id<CKKSPeer>>* remainingPeers = [self _onqueueFindPeers:trustState missingShare:key afterUploading:nil error:error];
    NSMutableSet<CKKSTLKShareRecord*>* newShares = [NSMutableSet set];

    if(!remainingPeers) {
        return nil;
    }

    NSError* localerror = nil;

    if(![key ensureKeyLoaded:error]) {
        return nil;
    }

    for(id<CKKSPeer> peer in remainingPeers) {
        if(!peer.publicEncryptionKey) {
            ckksnotice("ckksshare", self, "No need to make TLK for %@; they don't have any encryption keys", peer);
            continue;
        }

        // Create a share for this peer.
        ckksnotice("ckksshare", self, "Creating share of %@ as %@ for %@", key, trustState.currentSelfPeers.currentSelf, peer);
        CKKSTLKShareRecord* newShare = [CKKSTLKShareRecord share:key
                                                  as:trustState.currentSelfPeers.currentSelf
                                                  to:peer
                                               epoch:-1
                                            poisoned:0
                                               error:&localerror];

        if(localerror) {
            ckkserror("ckksshare", self, "Couldn't create new share for %@: %@", peer, localerror);
            if(error) {
                *error = localerror;
            }
            return nil;
        }

        [newShares addObject: newShare];
    }

    return newShares;
}

- (CKKSZoneKeyState*)_onqueueEnsureKeyHierarchyHealth:(CKKSCurrentKeySet*)set error:(NSError* __autoreleasing *)error {
    dispatch_assert_queue(self.queue);

    if(!set.currentTLKPointer && !set.currentClassAPointer && !set.currentClassCPointer) {
        ckkserror("ckkskey", self, "Error examining existing key hierarchy (missing all CKPs, likely no hierarchy exists): %@", set);
        return SecCKKSZoneKeyStateWaitForTLKCreation;
    }

    // Check keyset
    if(!set.tlk || !set.classA || !set.classC) {
        ckkserror("ckkskey", self, "Error examining existing key hierarchy (missing at least one key): %@", set);
        if(error) {
            *error = set.error;
        }
        return SecCKKSZoneKeyStateUnhealthy;
    }

    NSError* localerror = nil;
    bool probablyOkIfUnlocked = false;

    // keychain being locked is not a fatal error here
    [set.tlk loadKeyMaterialFromKeychain:&localerror];
    if(localerror && !([localerror.domain isEqual: @"securityd"] && localerror.code == errSecInteractionNotAllowed)) {
        ckkserror("ckkskey", self, "Error loading TLK(%@): %@", set.tlk, localerror);
        if(error) {
            *error = localerror;
        }
        return SecCKKSZoneKeyStateUnhealthy;
    } else if(localerror) {
        ckkserror("ckkskey", self, "Soft error loading TLK(%@), maybe locked: %@", set.tlk, localerror);
        probablyOkIfUnlocked = true;
    }
    localerror = nil;

    // keychain being locked is not a fatal error here
    [set.classA loadKeyMaterialFromKeychain:&localerror];
    if(localerror && !([localerror.domain isEqual: @"securityd"] && localerror.code == errSecInteractionNotAllowed)) {
        ckkserror("ckkskey", self, "Error loading classA key(%@): %@", set.classA, localerror);
        if(error) {
            *error = localerror;
        }
        return SecCKKSZoneKeyStateUnhealthy;
    } else if(localerror) {
        ckkserror("ckkskey", self, "Soft error loading classA key(%@), maybe locked: %@", set.classA, localerror);
        probablyOkIfUnlocked = true;
    }
    localerror = nil;

    // keychain being locked is a fatal error here, since this is class C
    [set.classC loadKeyMaterialFromKeychain:&localerror];
    if(localerror) {
        ckkserror("ckkskey", self, "Error loading classC(%@): %@", set.classC, localerror);
        if(error) {
            *error = localerror;
        }
        return SecCKKSZoneKeyStateUnhealthy;
    }

    // Check that the classA and classC keys point to the current TLK
    if(![set.classA.parentKeyUUID isEqualToString: set.tlk.uuid]) {
        localerror = [NSError errorWithDomain:CKKSServerExtensionErrorDomain
                                         code:CKKSServerUnexpectedSyncKeyInChain
                                     userInfo:@{
                                                NSLocalizedDescriptionKey: @"Current class A key does not wrap to current TLK",
                                               }];
        ckkserror("ckkskey", self, "Key hierarchy unhealthy: %@", localerror);
        if(error) {
            *error = localerror;
        }
        return SecCKKSZoneKeyStateUnhealthy;
    }
    if(![set.classC.parentKeyUUID isEqualToString: set.tlk.uuid]) {
        localerror = [NSError errorWithDomain:CKKSServerExtensionErrorDomain
                                         code:CKKSServerUnexpectedSyncKeyInChain
                                     userInfo:@{
                                                NSLocalizedDescriptionKey: @"Current class C key does not wrap to current TLK",
                                               }];
        ckkserror("ckkskey", self, "Key hierarchy unhealthy: %@", localerror);
        if(error) {
            *error = localerror;
        }
        return SecCKKSZoneKeyStateUnhealthy;
    }

    self.activeTLK = [set.tlk uuid];

    // Now that we're pretty sure we have the keys, are they shared appropriately?
    // We need trust in order to proceed here
    if(self.currentTrustStates.count == 0u) {
        ckkserror("ckkskey", self, "Can't check TLKShares due to missing trust states");
        return SecCKKSZoneKeyStateWaitForTrust;
    }

    // Check that every trusted peer has at least one TLK share
    // If any trust state check works, don't error out
    bool anyTrustStateSucceeded = false;
    for(CKKSPeerProviderState* trustState in self.currentTrustStates) {
        NSSet<id<CKKSPeer>>* missingShares = [self _onqueueFindPeers:trustState missingShare:set.tlk afterUploading:nil error:&localerror];
        if(localerror && [self.lockStateTracker isLockedError: localerror]) {
            ckkserror("ckkskey", self, "Couldn't find missing TLK shares due to lock state: %@", localerror);
            probablyOkIfUnlocked = true;

        } else if(([localerror.domain isEqualToString:TrustedPeersHelperErrorDomain] && localerror.code == TrustedPeersHelperErrorNoPreparedIdentity) ||
                  ([localerror.domain isEqualToString:CKKSErrorDomain] && localerror.code == CKKSLackingTrust) ||
                  ([localerror.domain isEqualToString:CKKSErrorDomain] && localerror.code == CKKSNoPeersAvailable)) {
            ckkserror("ckkskey", self, "Couldn't find missing TLK shares due some trust issue: %@", localerror);

            if(trustState.essential) {
                ckkserror("ckkskey", self, "Trust state is considered essential; entering waitfortrust: %@", trustState);

                // Octagon can reinform us when it thinks we should start again
                self.trustStatus = CKKSAccountStatusUnknown;
                return SecCKKSZoneKeyStateWaitForTrust;
            } else {
                ckkserror("ckkskey", self, "Peer provider is considered nonessential; ignoring error: %@", trustState);
                continue;
            }

        } else if(localerror) {
            ckkserror("ckkskey", self, "Error finding missing TLK shares: %@", localerror);
            continue;
        }

        if(!missingShares || missingShares.count != 0u) {
            localerror = [NSError errorWithDomain:CKKSErrorDomain code:CKKSMissingTLKShare
                                      description:[NSString stringWithFormat:@"Missing shares for %lu peers", (unsigned long)missingShares.count]];
            if(error) {
                *error = localerror;
            }
            return SecCKKSZoneKeyStateHealTLKShares;
        } else {
            ckksnotice("ckksshare", self, "TLK (%@) is shared correctly for trust state %@", set.tlk, trustState.peerProviderID);
        }

        anyTrustStateSucceeded |= true;
    }

    if(!anyTrustStateSucceeded) {
        if(error) {
            *error = localerror;
        }

        return SecCKKSZoneKeyStateError;
    }

    // Got to the bottom? Cool! All keys are present and accounted for.
    return probablyOkIfUnlocked ? SecCKKSZoneKeyStateReadyPendingUnlock : SecCKKSZoneKeyStateReady;
}

- (void)_onqueueKeyHierarchyFetch {
    [self _onqueueKeyHierarchyFetchForReasons:[NSSet setWithArray:@[CKKSFetchBecauseKeyHierarchy]]];
}

- (void)_onqueueKeyHierarchyFetchForReasons:(NSSet<CKKSFetchBecause*>*)reasons
{
    dispatch_assert_queue(self.queue);

    WEAKIFY(self);
    self.keyStateMachineOperation = [NSBlockOperation blockOperationWithBlock: ^{
        STRONGIFY(self);
        if(!self) {
            ckkserror("ckks", self, "received callback for released object");
            return;
        }
        [self.launch addEvent:@"fetch-complete"];

        [self dispatchSyncWithAccountKeys: ^bool{
            [self _onqueueAdvanceKeyStateMachineToState: SecCKKSZoneKeyStateFetchComplete withError: nil];
            return true;
        }];
    }];
    self.keyStateMachineOperation.name = @"waiting-for-fetch";

    NSOperation* fetchOp = [self.zoneChangeFetcher requestSuccessfulFetchForManyReasons:reasons];
    [self.keyStateMachineOperation addDependency: fetchOp];

    self.keyStateFetchRequested = false;
}

- (void) handleKeychainEventDbConnection: (SecDbConnectionRef) dbconn
                                   added: (SecDbItemRef) added
                                 deleted: (SecDbItemRef) deleted
                             rateLimiter: (CKKSRateLimiter*) rateLimiter
                            syncCallback: (SecBoolNSErrorCallback) syncCallback {
    if(!SecCKKSIsEnabled()) {
        ckksnotice("ckks", self, "Skipping handleKeychainEventDbConnection due to disabled CKKS");
        return;
    }

    __block NSError* error = nil;

    // Tombstones come in as item modifications or item adds. Handle modifications here.
    bool addedTombstone   = added   && SecDbItemIsTombstone(added);
    bool deletedTombstone = deleted && SecDbItemIsTombstone(deleted);

    bool addedSync   = added   && SecDbItemIsSyncable(added);
    bool deletedSync = deleted && SecDbItemIsSyncable(deleted);

    bool isAdd    = ( added && !deleted) || (added && deleted && !addedTombstone &&  deletedTombstone) || (added && deleted &&  addedSync && !deletedSync);
    bool isDelete = (!added &&  deleted) || (added && deleted &&  addedTombstone && !deletedTombstone) || (added && deleted && !addedSync &&  deletedSync);
    bool isModify = ( added &&  deleted) && (!isAdd) && (!isDelete);

    // On an update that changes an item's primary key, SecDb modifies the existing item, then adds a new tombstone to replace the old primary key.
    // Therefore, we might receive an added tombstone here with no deleted item to accompany it. This should be considered a deletion.
    if(addedTombstone && !deleted) {
        isAdd = false;
        isDelete = true;
        isModify = false;

        // Passed to withItem: below
        deleted = added;
    }

    // If neither item is syncable, don't proceed further in the syncing system
    bool proceed = addedSync || deletedSync;

    if(!proceed) {
        ckksnotice("ckks", self, "skipping sync of non-sync item (%d, %d)", addedSync, deletedSync);
        return;
    }

    // It's possible to ask for an item to be deleted without adding a corresponding tombstone.
    // This is arguably a bug, as it generates an out-of-sync state, but it is in the API contract.
    // CKKS should ignore these, but log very upset messages.
    if(isDelete && !addedTombstone) {
        ckksnotice("ckks", self, "Client has asked for an item deletion to not sync. Keychain is now out of sync with account");
        return;
    }

    // Only synchronize items which can transfer between devices
    NSString* protection = (__bridge NSString*)SecDbItemGetCachedValueWithName(added ? added : deleted, kSecAttrAccessible);
    if(! ([protection isEqualToString: (__bridge NSString*)kSecAttrAccessibleWhenUnlocked] ||
          [protection isEqualToString: (__bridge NSString*)kSecAttrAccessibleAfterFirstUnlock] ||
          [protection isEqualToString: (__bridge NSString*)kSecAttrAccessibleAlwaysPrivate])) {
        ckksnotice("ckks", self, "skipping sync of device-bound(%@) item", protection);
        return;
    }

    // Our caller gave us a database connection. We must get on the local queue to ensure atomicity
    // Note that we're at the mercy of the surrounding db transaction, so don't try to rollback here
    [self dispatchSyncWithConnection: dbconn block: ^bool {
        // Schedule a "view changed" notification
        [self.notifyViewChangedScheduler trigger];

        if(self.accountStatus == CKKSAccountStatusNoAccount) {
            // No account; CKKS shouldn't attempt anything.
            self.droppedItems = true;
            ckksnotice("ckks", self, "Dropping sync item modification due to CK account state; will scan to find changes later");

            if(syncCallback) {
                // We're positively not logged into CloudKit, and therefore don't expect this item to be synced anytime particularly soon.
                [self callSyncCallbackWithErrorNoAccount: syncCallback];
            }
            return true;
        }

        // Always record the callback, even if we can't encrypt the item right now. Maybe we'll get to it soon!
        if(syncCallback) {
            CFErrorRef cferror = NULL;
            NSString* uuid = (__bridge_transfer NSString*) CFRetain(SecDbItemGetValue(added, &v10itemuuid, &cferror));
            if(!cferror && uuid) {
                self.pendingSyncCallbacks[uuid] = syncCallback;
            }
            CFReleaseNull(cferror);
        }

        CKKSOutgoingQueueEntry* oqe = nil;
        if       (isAdd) {
            oqe = [CKKSOutgoingQueueEntry withItem: added   action: SecCKKSActionAdd    ckks:self error: &error];
        } else if(isDelete) {
            oqe = [CKKSOutgoingQueueEntry withItem: deleted action: SecCKKSActionDelete ckks:self error: &error];
        } else if(isModify) {
            oqe = [CKKSOutgoingQueueEntry withItem: added   action: SecCKKSActionModify ckks:self error: &error];
        } else {
            ckkserror("ckks", self, "processKeychainEventItemAdded given garbage: %@ %@", added, deleted);
            return true;
        }

        CKOperationGroup* operationGroup = [CKOperationGroup CKKSGroupWithName:@"keychain-api-use"];

        if(error) {
            ckkserror("ckks", self, "Couldn't create outgoing queue entry: %@", error);
            self.droppedItems = true;

            // If the problem is 'no UUID', launch a scan operation to find and fix it
            // We don't want to fix it up here, in the closing moments of a transaction
            if([error.domain isEqualToString:CKKSErrorDomain] && error.code == CKKSNoUUIDOnItem) {
                ckksnotice("ckks", self, "Launching scan operation to find UUID");
                [self scanLocalItems:@"uuid-find-scan" ckoperationGroup:operationGroup after:nil];
            }

            // If the problem is 'couldn't load key', tell the key hierarchy state machine to fix it
            if([error.domain isEqualToString:CKKSErrorDomain] && error.code == errSecItemNotFound) {
                [self.pokeKeyStateMachineScheduler trigger];
            }

            return true;
        }

        if(rateLimiter) {
            NSDate* limit = nil;
            NSInteger value = [rateLimiter judge:oqe at:[NSDate date] limitTime:&limit];
            if(limit) {
                oqe.waitUntil = limit;
                SecPLLogRegisteredEvent(@"CKKSSyncing", @{ @"ratelimit" : @(value), @"accessgroup" : oqe.accessgroup});
            }
        }

        [oqe saveToDatabaseWithConnection: dbconn error: &error];
        if(error) {
            ckkserror("ckks", self, "Couldn't save outgoing queue entry to database: %@", error);
            return true;
        } else {
            ckksnotice("ckks", self, "Saved %@ to outgoing queue", oqe);
        }

        // This update supercedes all other local modifications to this item (_except_ those in-flight).
        // Delete all items in reencrypt or error.
        CKKSOutgoingQueueEntry* reencryptOQE = [CKKSOutgoingQueueEntry tryFromDatabase:oqe.uuid state:SecCKKSStateReencrypt zoneID:self.zoneID error:&error];
        if(error) {
            ckkserror("ckks", self, "Couldn't load reencrypt OQE sibling for %@: %@", oqe, error);
        }
        if(reencryptOQE) {
            [reencryptOQE deleteFromDatabase:&error];
            if(error) {
                ckkserror("ckks", self, "Couldn't delete reencrypt OQE sibling(%@) for %@: %@", reencryptOQE, oqe, error);
            }
            error = nil;
        }

        CKKSOutgoingQueueEntry* errorOQE = [CKKSOutgoingQueueEntry tryFromDatabase:oqe.uuid state:SecCKKSStateError zoneID:self.zoneID error:&error];
        if(error) {
            ckkserror("ckks", self, "Couldn't load error OQE sibling for %@: %@", oqe, error);
        }
        if(errorOQE) {
            [errorOQE deleteFromDatabase:&error];
            if(error) {
                ckkserror("ckks", self, "Couldn't delete error OQE sibling(%@) for %@: %@", reencryptOQE, oqe, error);
            }
        }

        [self processOutgoingQueue:operationGroup];

        return true;
    }];
}

-(void)setCurrentItemForAccessGroup:(NSData* _Nonnull)newItemPersistentRef
                               hash:(NSData*)newItemSHA1
                        accessGroup:(NSString*)accessGroup
                         identifier:(NSString*)identifier
                          replacing:(NSData* _Nullable)oldCurrentItemPersistentRef
                               hash:(NSData*)oldItemSHA1
                           complete:(void (^) (NSError* operror)) complete
{
    if(accessGroup == nil || identifier == nil) {
        NSError* error = [NSError errorWithDomain:CKKSErrorDomain
                                             code:errSecParam
                                      description:@"No access group or identifier given"];
        ckkserror("ckkscurrent", self, "Cancelling request: %@", error);
        complete(error);
        return;
    }

    // Not being in a CloudKit account is an automatic failure.
    // But, wait a good long while for the CloudKit account state to be known (in the case of daemon startup)
    [self.accountStateKnown wait:(SecCKKSTestsEnabled() ? 1*NSEC_PER_SEC : 30*NSEC_PER_SEC)];

    if(self.accountStatus != CKKSAccountStatusAvailable) {
        NSError* error = [NSError errorWithDomain:CKKSErrorDomain
                                             code:CKKSNotLoggedIn
                                      description:@"User is not signed into iCloud."];
        ckksnotice("ckkscurrent", self, "Rejecting current item pointer set since we don't have an iCloud account.");
        complete(error);
        return;
    }

    ckksnotice("ckkscurrent", self, "Starting change current pointer operation for %@-%@", accessGroup, identifier);
    CKKSUpdateCurrentItemPointerOperation* ucipo = [[CKKSUpdateCurrentItemPointerOperation alloc] initWithCKKSKeychainView:self
                                                                                                                   newItem:newItemPersistentRef
                                                                                                                      hash:newItemSHA1
                                                                                                               accessGroup:accessGroup
                                                                                                                identifier:identifier
                                                                                                                 replacing:oldCurrentItemPersistentRef
                                                                                                                      hash:oldItemSHA1
                                                                                                          ckoperationGroup:[CKOperationGroup CKKSGroupWithName:@"currentitem-api"]];

    WEAKIFY(self);
    CKKSResultOperation* returnCallback = [CKKSResultOperation operationWithBlock:^{
        STRONGIFY(self);

        if(ucipo.error) {
            ckkserror("ckkscurrent", self, "Failed setting a current item pointer for %@ with %@", ucipo.currentPointerIdentifier, ucipo.error);
        } else {
            ckksnotice("ckkscurrent", self, "Finished setting a current item pointer for %@", ucipo.currentPointerIdentifier);
        }
        complete(ucipo.error);
    }];
    returnCallback.name = @"setCurrentItem-return-callback";
    [returnCallback addDependency: ucipo];
    [self scheduleOperation: returnCallback];

    // Now, schedule ucipo. It modifies the CloudKit zone, so it should insert itself into the list of OutgoingQueueOperations.
    // Then, we won't have simultaneous zone-modifying operations.
    [ucipo linearDependencies:self.outgoingQueueOperations];

    // If this operation hasn't started within 60 seconds, cancel it and return a "timed out" error.
    [ucipo timeout:60*NSEC_PER_SEC];

    [self scheduleOperation:ucipo];
    return;
}

-(void)getCurrentItemForAccessGroup:(NSString*)accessGroup
                         identifier:(NSString*)identifier
                    fetchCloudValue:(bool)fetchCloudValue
                           complete:(void (^) (NSString* uuid, NSError* operror)) complete
{
    if(accessGroup == nil || identifier == nil) {
        ckksnotice("ckkscurrent", self, "Rejecting current item pointer get since no access group(%@) or identifier(%@) given", accessGroup, identifier);
        complete(NULL, [NSError errorWithDomain:CKKSErrorDomain
                                           code:errSecParam
                                    description:@"No access group or identifier given"]);
        return;
    }

    // Not being in a CloudKit account is an automatic failure.
    // But, wait a good long while for the CloudKit account state to be known (in the case of daemon startup)
    [self.accountStateKnown wait:(SecCKKSTestsEnabled() ? 1*NSEC_PER_SEC : 30*NSEC_PER_SEC)];

    if(self.accountStatus != CKKSAccountStatusAvailable) {
        ckksnotice("ckkscurrent", self, "Rejecting current item pointer get since we don't have an iCloud account.");
        complete(NULL, [NSError errorWithDomain:CKKSErrorDomain
                                           code:CKKSNotLoggedIn
                                    description:@"User is not signed into iCloud."]);
        return;
    }

    CKKSResultOperation* fetchAndProcess = nil;
    if(fetchCloudValue) {
        fetchAndProcess = [self fetchAndProcessCKChanges:CKKSFetchBecauseCurrentItemFetchRequest];
    }

    WEAKIFY(self);
    CKKSResultOperation* getCurrentItem = [CKKSResultOperation named:@"get-current-item-pointer" withBlock:^{
        if(fetchAndProcess.error) {
            ckksnotice("ckkscurrent", self, "Rejecting current item pointer get since fetch failed: %@", fetchAndProcess.error);
            complete(NULL, fetchAndProcess.error);
            return;
        }

        STRONGIFY(self);

        [self dispatchSync: ^bool {
            NSError* error = nil;
            NSString* currentIdentifier = [NSString stringWithFormat:@"%@-%@", accessGroup, identifier];

            CKKSCurrentItemPointer* cip = [CKKSCurrentItemPointer fromDatabase:currentIdentifier
                                                                         state:SecCKKSProcessedStateLocal
                                                                        zoneID:self.zoneID
                                                                         error:&error];
            if(!cip || error) {
                ckkserror("ckkscurrent", self, "No current item pointer for %@", currentIdentifier);
                complete(nil, error);
                return false;
            }

            if(!cip.currentItemUUID) {
                ckkserror("ckkscurrent", self, "Current item pointer is empty %@", cip);
                complete(nil, [NSError errorWithDomain:CKKSErrorDomain
                                                  code:errSecInternalError
                                           description:@"Current item pointer is empty"]);
                return false;
            }

            ckksinfo("ckkscurrent", self, "Retrieved current item pointer: %@", cip);
            complete(cip.currentItemUUID, NULL);
            return true;
        }];
    }];

    [getCurrentItem addNullableDependency:fetchAndProcess];
    [self scheduleOperation: getCurrentItem];
}

- (CKKSKey*) keyForItem: (SecDbItemRef) item error: (NSError * __autoreleasing *) error {
    CKKSKeyClass* class = nil;

    NSString* protection = (__bridge NSString*)SecDbItemGetCachedValueWithName(item, kSecAttrAccessible);
    if([protection isEqualToString: (__bridge NSString*)kSecAttrAccessibleWhenUnlocked]) {
        class = SecCKKSKeyClassA;
    } else if([protection isEqualToString: (__bridge NSString*)kSecAttrAccessibleAlwaysPrivate] ||
              [protection isEqualToString: (__bridge NSString*)kSecAttrAccessibleAfterFirstUnlock]) {
        class = SecCKKSKeyClassC;
    } else {
        NSError* localError = [NSError errorWithDomain:CKKSErrorDomain
                                                  code:CKKSInvalidKeyClass
                                           description:[NSString stringWithFormat:@"can't pick key class for protection %@", protection]];
        ckkserror("ckks", self, "can't pick key class: %@ %@", localError, item);
        if(error) {
            *error = localError;
        }

        return nil;
    }

    NSError* currentKeyError = nil;
    CKKSKey* key = [CKKSKey currentKeyForClass: class zoneID:self.zoneID error:&currentKeyError];
    if(!key || currentKeyError) {
        ckkserror("ckks", self, "Couldn't find current key for %@: %@", class, currentKeyError);

        if(error) {
            *error = currentKeyError;
        }
        return nil;
    }

    // and make sure it's unwrapped.
    NSError* loadedError = nil;
    if(![key ensureKeyLoaded:&loadedError]) {
        ckkserror("ckks", self, "Couldn't load key(%@): %@", key, loadedError);
        if(error) {
            *error = loadedError;
        }
        return nil;
    }

    return key;
}

- (CKKSResultOperation<CKKSKeySetProviderOperationProtocol>*)findKeySet
{
    __block CKKSResultOperation<CKKSKeySetProviderOperationProtocol>* keysetOp = nil;

    [self dispatchSyncWithAccountKeys:^bool {
        CKKSCurrentKeySet* keyset = [CKKSCurrentKeySet loadForZone:self.zoneID];
        if(keyset.currentTLKPointer.currentKeyUUID && keyset.tlk.uuid) {
            ckksnotice("ckks", self, "Already have keyset %@", keyset);

            keysetOp = [[CKKSProvideKeySetOperation alloc] initWithZoneName:self.zoneName keySet:keyset];
            [self scheduleOperationWithoutDependencies:keysetOp];
            return true;
        } else if([self.keyHierarchyState isEqualToString:SecCKKSZoneKeyStateWaitForTLKUpload]) {
            CKKSCurrentKeySet* proposedKeySet = self.lastNewTLKOperation.keyset;
            ckksnotice("ckks", self, "Already have proposed keyset %@", proposedKeySet);

            keysetOp = [[CKKSProvideKeySetOperation alloc] initWithZoneName:self.zoneName keySet:proposedKeySet];
            [self scheduleOperationWithoutDependencies:keysetOp];
            return true;
        } else {
            // No existing keyset (including keys) exists.
            // The state machine will know what to do!
            self.tlkCreationRequested = true;

            ckksnotice("ckks", self, "Received a keyset request; forwarding to state machine");

            keysetOp = (CKKSProvideKeySetOperation*) [self findFirstPendingOperation:self.keysetProviderOperations];
            if(!keysetOp) {
                keysetOp = [[CKKSProvideKeySetOperation alloc] initWithZoneName:self.zoneName];
                [self.keysetProviderOperations addObject:keysetOp];

                // This is an abuse of operations: they should generally run when added to a queue, not wait, but this allows recipients to set timeouts
                [self scheduleOperationWithoutDependencies:keysetOp];
            }

            [self _onqueueAdvanceKeyStateMachineToState:nil withError:nil];
        }

        return true;
    }];

    return keysetOp;
}

- (void)_onqueueRunKeysetProviderOperations:(CKKSCurrentKeySet*)keyset
{
    ckksnotice("ckkskey", self, "Providing keyset (%@) to listeners", keyset);

    // We have some keyset; they can ask again if they want a new one
    self.tlkCreationRequested = false;

    for(CKKSResultOperation<CKKSKeySetProviderOperationProtocol>* op in self.keysetProviderOperations) {
        if([op isPending]) {
            [op provideKeySet:keyset];
        }
    }
}

- (void)receiveTLKUploadRecords:(NSArray<CKRecord*>*)records
{
    // First, filter for records matching this zone
    NSMutableArray<CKRecord*>* zoneRecords = [NSMutableArray array];
    for(CKRecord* record in records) {
        if([record.recordID.zoneID isEqual:self.zoneID]) {
            [zoneRecords addObject:record];
        }
    }

    ckksnotice("ckkskey", self, "Received a set of %lu TLK upload records", (unsigned long)zoneRecords.count);

    if(!zoneRecords || zoneRecords.count == 0) {
        return;
    }

    [self dispatchSyncWithAccountKeys:^bool {

        for(CKRecord* record in zoneRecords) {
            [self _onqueueCKRecordChanged:record resync:false];
        }

        return true;
    }];
}

// Use the following method to find the first pending operation in a weak collection
- (NSOperation*)findFirstPendingOperation: (NSHashTable*) table {
    return [self findFirstPendingOperation:table ofClass:nil];
}

// Use the following method to find the first pending operation in a weak collection
- (NSOperation*)findFirstPendingOperation: (NSHashTable*) table ofClass:(Class)class {
    @synchronized(table) {
        for(NSOperation* op in table) {
            if(op != nil && [op isPending] && (class == nil || [op isKindOfClass: class])) {
                return op;
            }
        }
        return nil;
    }
}

// Use the following method to count the pending operations in a weak collection
- (int64_t)countPendingOperations: (NSHashTable*) table {
    @synchronized(table) {
        int count = 0;
        for(NSOperation* op in table) {
            if(op != nil && !([op isExecuting] || [op isFinished])) {
                count++;
            }
        }
        return count;
    }
}

- (NSSet<NSString*>*)_onqueuePriorityOutgoingQueueUUIDs
{
    return [self.pendingSyncCallbacks.allKeys copy];
}

- (CKKSOutgoingQueueOperation*)processOutgoingQueue:(CKOperationGroup*)ckoperationGroup {
    return [self processOutgoingQueueAfter:nil ckoperationGroup:ckoperationGroup];
}

- (CKKSOutgoingQueueOperation*)processOutgoingQueueAfter:(CKKSResultOperation*)after ckoperationGroup:(CKOperationGroup*)ckoperationGroup {
    return [self processOutgoingQueueAfter:after requiredDelay:DISPATCH_TIME_FOREVER ckoperationGroup:ckoperationGroup];
}

- (CKKSOutgoingQueueOperation*)processOutgoingQueueAfter:(CKKSResultOperation*)after
                                           requiredDelay:(uint64_t)requiredDelay
                                        ckoperationGroup:(CKOperationGroup*)ckoperationGroup
{
    CKKSOutgoingQueueOperation* outgoingop =
            (CKKSOutgoingQueueOperation*) [self findFirstPendingOperation:self.outgoingQueueOperations
                                                                  ofClass:[CKKSOutgoingQueueOperation class]];
    if(outgoingop) {
        if(after) {
            [outgoingop addDependency: after];
        }
        if([outgoingop isPending]) {
            if(!outgoingop.ckoperationGroup && ckoperationGroup) {
                outgoingop.ckoperationGroup = ckoperationGroup;
            } else if(ckoperationGroup) {
                ckkserror("ckks", self, "Throwing away CKOperationGroup(%@) in favor of (%@)", ckoperationGroup.name, outgoingop.ckoperationGroup.name);
            }

            // Will log any pending dependencies as well
            ckksnotice("ckksoutgoing", self, "Returning existing %@", outgoingop);

            // Shouldn't be necessary, but can't hurt
            [self.outgoingQueueOperationScheduler triggerAt:requiredDelay];
            return outgoingop;
        }
    }

    CKKSOutgoingQueueOperation* op = [[CKKSOutgoingQueueOperation alloc] initWithCKKSKeychainView:self ckoperationGroup:ckoperationGroup];
    op.name = @"outgoing-queue-operation";
    [op addNullableDependency:after];
    [op addNullableDependency:self.outgoingQueueOperationScheduler.operationDependency];

    [self.outgoingQueueOperationScheduler triggerAt:requiredDelay];

    [self scheduleOperation: op];
    ckksnotice("ckksoutgoing", self, "Scheduled %@", op);
    return op;
}

- (void)processIncomingQueueAfterNextUnlock {
    // Thread races aren't so important here; we might end up with two or three copies of this operation, but that's okay.
    if(![self.processIncomingQueueAfterNextUnlockOperation isPending]) {
        WEAKIFY(self);

        CKKSResultOperation* restartIncomingQueueOperation = [CKKSResultOperation operationWithBlock:^{
            STRONGIFY(self);
            // This IQO shouldn't error if the keybag has locked again. It will simply try again later.
            [self processIncomingQueue:false];
        }];

        restartIncomingQueueOperation.name = @"reprocess-incoming-queue-after-unlock";
        self.processIncomingQueueAfterNextUnlockOperation = restartIncomingQueueOperation;

        [restartIncomingQueueOperation addNullableDependency:self.lockStateTracker.unlockDependency];
        [self scheduleOperation: restartIncomingQueueOperation];
    }
}

- (CKKSResultOperation*)resultsOfNextProcessIncomingQueueOperation {
    if(self.resultsOfNextIncomingQueueOperationOperation && [self.resultsOfNextIncomingQueueOperationOperation isPending]) {
        return self.resultsOfNextIncomingQueueOperationOperation;
    }

    // Else, make a new one.
    self.resultsOfNextIncomingQueueOperationOperation = [CKKSResultOperation named:[NSString stringWithFormat:@"wait-for-next-incoming-queue-operation-%@", self.zoneName] withBlock:^{}];
    return self.resultsOfNextIncomingQueueOperationOperation;
}

- (CKKSIncomingQueueOperation*)processIncomingQueue:(bool)failOnClassA {
    return [self processIncomingQueue:failOnClassA after: nil];
}

- (CKKSIncomingQueueOperation*) processIncomingQueue:(bool)failOnClassA after: (CKKSResultOperation*) after {
    CKKSIncomingQueueOperation* incomingop = (CKKSIncomingQueueOperation*) [self findFirstPendingOperation:self.incomingQueueOperations];
    if(incomingop) {
        ckksinfo("ckks", self, "Skipping processIncomingQueue due to at least one pending instance");
        if(after) {
            [incomingop addNullableDependency: after];
        }

        // check (again) for race condition; if the op has started we need to add another (for the dependency)
        if([incomingop isPending]) {
            incomingop.errorOnClassAFailure |= failOnClassA;
            return incomingop;
        }
    }

    CKKSIncomingQueueOperation* op = [[CKKSIncomingQueueOperation alloc] initWithCKKSKeychainView:self errorOnClassAFailure:failOnClassA];
    op.name = @"incoming-queue-operation";
    if(after != nil) {
        [op addSuccessDependency: after];
    }

    if(self.resultsOfNextIncomingQueueOperationOperation) {
        [self.resultsOfNextIncomingQueueOperationOperation addSuccessDependency:op];
        [self scheduleOperation:self.resultsOfNextIncomingQueueOperationOperation];
    }

    [self scheduleOperation: op];
    return op;
}

- (CKKSScanLocalItemsOperation*)scanLocalItems:(NSString*)operationName {
    return [self scanLocalItems:operationName ckoperationGroup:nil after:nil];
}

- (CKKSScanLocalItemsOperation*)scanLocalItems:(NSString*)operationName ckoperationGroup:(CKOperationGroup*)operationGroup after:(NSOperation*)after {
    CKKSScanLocalItemsOperation* scanOperation = [[CKKSScanLocalItemsOperation alloc] initWithCKKSKeychainView:self ckoperationGroup:operationGroup];
    scanOperation.name = operationName;

    [scanOperation addNullableDependency:self.lastFixupOperation];
    [scanOperation addNullableDependency:self.lockStateTracker.unlockDependency];
    [scanOperation addNullableDependency:self.keyStateReadyDependency];
    [scanOperation addNullableDependency:after];

    [self scheduleOperation: scanOperation];
    return scanOperation;
}

- (CKKSUpdateDeviceStateOperation*)updateDeviceState:(bool)rateLimit
                   waitForKeyHierarchyInitialization:(uint64_t)timeout
                                    ckoperationGroup:(CKOperationGroup*)ckoperationGroup {

    WEAKIFY(self);

    // If securityd just started, the key state might be in some transient early state. Wait a bit.
    CKKSResultOperation* waitForKeyReady = [CKKSResultOperation named:@"device-state-wait" withBlock:^{
        STRONGIFY(self);
        ckksnotice("ckksdevice", self, "Finished waiting for key hierarchy transient state, currently %@", self.keyHierarchyState);
    }];

    [waitForKeyReady addNullableDependency:self.keyStateNonTransientDependency];
    [waitForKeyReady timeout:timeout];
    [self.waitingQueue addOperation:waitForKeyReady];

    CKKSUpdateDeviceStateOperation* op = [[CKKSUpdateDeviceStateOperation alloc] initWithCKKSKeychainView:self rateLimit:rateLimit ckoperationGroup:ckoperationGroup];
    op.name = @"device-state-operation";

    [op addDependency: waitForKeyReady];

    // op modifies the CloudKit zone, so it should insert itself into the list of OutgoingQueueOperations.
    // Then, we won't have simultaneous zone-modifying operations and confuse ourselves.
    // However, since we might have pending OQOs, it should try to insert itself at the beginning of the linearized list
    [op linearDependenciesWithSelfFirst:self.outgoingQueueOperations];

    // CKKSUpdateDeviceStateOperations are special: they should fire even if we don't believe we're in an iCloud account.
    // They also shouldn't block or be blocked by any other operation; our wait operation above will handle that
    [self scheduleOperationWithoutDependencies:op];
    return op;
}

// There are some errors which won't be reported but will be reflected in the CDSE; any error coming out of here is fatal
- (CKKSDeviceStateEntry*)_onqueueCurrentDeviceStateEntry: (NSError* __autoreleasing*)error {
    NSError* localerror = nil;

    CKKSAccountStateTracker* accountTracker = self.accountTracker;
    CKKSAccountStatus hsa2Status = accountTracker.hsa2iCloudAccountStatus;

    // We must have an HSA2 iCloud account and a CloudKit account to even create one of these
    if(hsa2Status != CKKSAccountStatusAvailable ||
       accountTracker.currentCKAccountInfo.accountStatus != CKAccountStatusAvailable) {
        ckkserror("ckksdevice", self, "No iCloud account active: %@ hsa2 account:%@",
                  accountTracker.currentCKAccountInfo,
                  CKKSAccountStatusToString(hsa2Status));
        localerror = [NSError errorWithDomain:@"securityd"
                                         code:errSecInternalError
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat: @"No active HSA2 iCloud account: %@", accountTracker.currentCKAccountInfo]}];
        if(error) {
            *error = localerror;
        }
        return nil;
    }

    NSString* ckdeviceID = accountTracker.ckdeviceID;
    if(ckdeviceID == nil) {
        ckkserror("ckksdevice", self, "No CK device ID available; cannot make device state entry");
        localerror = [NSError errorWithDomain:CKKSErrorDomain
                                         code:CKKSNotLoggedIn
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat: @"No CK device ID: %@", accountTracker.currentCKAccountInfo]}];
        if(error) {
            *error = localerror;
        }
        return nil;
    }

    CKKSDeviceStateEntry* oldcdse = [CKKSDeviceStateEntry tryFromDatabase:ckdeviceID zoneID:self.zoneID error:&localerror];
    if(localerror) {
        ckkserror("ckksdevice", self, "Couldn't read old CKKSDeviceStateEntry from database: %@", localerror);
        if(error) {
            *error = localerror;
        }
        return nil;
    }

    // Find out what we think the current keys are
    CKKSCurrentKeyPointer* currentTLKPointer    = [CKKSCurrentKeyPointer tryFromDatabase: SecCKKSKeyClassTLK zoneID:self.zoneID error:&localerror];
    CKKSCurrentKeyPointer* currentClassAPointer = [CKKSCurrentKeyPointer tryFromDatabase: SecCKKSKeyClassA   zoneID:self.zoneID error:&localerror];
    CKKSCurrentKeyPointer* currentClassCPointer = [CKKSCurrentKeyPointer tryFromDatabase: SecCKKSKeyClassC   zoneID:self.zoneID error:&localerror];
    if(localerror) {
        // Things is broken, but the whole point of this record is to share the brokenness. Continue.
        ckkserror("ckksdevice", self, "Couldn't read current key pointers from database: %@; proceeding", localerror);
        localerror = nil;
    }

    CKKSKey* suggestedTLK       = currentTLKPointer.currentKeyUUID    ? [CKKSKey tryFromDatabase:currentTLKPointer.currentKeyUUID    zoneID:self.zoneID error:&localerror] : nil;
    CKKSKey* suggestedClassAKey = currentClassAPointer.currentKeyUUID ? [CKKSKey tryFromDatabase:currentClassAPointer.currentKeyUUID zoneID:self.zoneID error:&localerror] : nil;
    CKKSKey* suggestedClassCKey = currentClassCPointer.currentKeyUUID ? [CKKSKey tryFromDatabase:currentClassCPointer.currentKeyUUID zoneID:self.zoneID error:&localerror] : nil;

    if(localerror) {
        // Things is broken, but the whole point of this record is to share the brokenness. Continue.
        ckkserror("ckksdevice", self, "Couldn't read keys from database: %@; proceeding", localerror);
        localerror = nil;
    }

    // Check if we posess the keys in the keychain
    [suggestedTLK ensureKeyLoaded:&localerror];
    if(localerror && [self.lockStateTracker isLockedError:localerror]) {
        ckkserror("ckksdevice", self, "Device is locked; couldn't read TLK from keychain. Assuming it is present and continuing; error was %@", localerror);
        localerror = nil;
    } else if(localerror) {
        ckkserror("ckksdevice", self, "Couldn't read TLK from keychain. We do not have a current TLK. Error was %@", localerror);
        suggestedTLK = nil;
    }

    [suggestedClassAKey ensureKeyLoaded:&localerror];
    if(localerror && [self.lockStateTracker isLockedError:localerror]) {
        ckkserror("ckksdevice", self, "Device is locked; couldn't read ClassA key from keychain. Assuming it is present and continuing; error was %@", localerror);
        localerror = nil;
    } else if(localerror) {
        ckkserror("ckksdevice", self, "Couldn't read ClassA key from keychain. We do not have a current ClassA key. Error was %@", localerror);
        suggestedClassAKey = nil;
    }

    [suggestedClassCKey ensureKeyLoaded:&localerror];
    // class C keys are stored class C, so uh, don't check lock state.
    if(localerror) {
        ckkserror("ckksdevice", self, "Couldn't read ClassC key from keychain. We do not have a current ClassC key. Error was %@", localerror);
        suggestedClassCKey = nil;
    }

    // We'd like to have the circle peer ID. Give the account state tracker a fighting chance, but not having it is not an error
    // But, if the platform doesn't have SOS, don't bother
    if(OctagonPlatformSupportsSOS() && [accountTracker.accountCirclePeerIDInitialized wait:500*NSEC_PER_MSEC] != 0 && !accountTracker.accountCirclePeerID) {
        ckkserror("ckksdevice", self, "No SOS peer ID available");
    }

    // We'd also like the Octagon status
    if([accountTracker.octagonInformationInitialized wait:500*NSEC_PER_MSEC] != 0 && !accountTracker.octagonPeerID) {
        ckkserror("ckksdevice", self, "No octagon peer ID available");
    }

    // Reset the last unlock time to 'day' granularity in UTC
    NSCalendar* calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierISO8601];
    calendar.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    NSDate* lastUnlockDay = self.lockStateTracker.lastUnlockTime;
    lastUnlockDay = lastUnlockDay ? [calendar startOfDayForDate:lastUnlockDay] : nil;

    // We only really want the oldcdse for its encodedCKRecord, so make a new cdse here
    CKKSDeviceStateEntry* newcdse = [[CKKSDeviceStateEntry alloc] initForDevice:ckdeviceID
                                                                      osVersion:SecCKKSHostOSVersion()
                                                                 lastUnlockTime:lastUnlockDay
                                                                  octagonPeerID:accountTracker.octagonPeerID
                                                                  octagonStatus:accountTracker.octagonStatus
                                                                   circlePeerID:accountTracker.accountCirclePeerID
                                                                   circleStatus:accountTracker.currentCircleStatus.status
                                                                       keyState:self.keyHierarchyState
                                                                 currentTLKUUID:suggestedTLK.uuid
                                                              currentClassAUUID:suggestedClassAKey.uuid
                                                              currentClassCUUID:suggestedClassCKey.uuid
                                                                         zoneID:self.zoneID
                                                                encodedCKRecord:oldcdse.encodedCKRecord];
    return newcdse;
}

- (CKKSSynchronizeOperation*) resyncWithCloud {
    CKKSSynchronizeOperation* op = [[CKKSSynchronizeOperation alloc] initWithCKKSKeychainView: self];
    [self scheduleOperation: op];
    return op;
}

- (CKKSLocalSynchronizeOperation*)resyncLocal {
    CKKSLocalSynchronizeOperation* op = [[CKKSLocalSynchronizeOperation alloc] initWithCKKSKeychainView:self];
    [self scheduleOperation: op];
    return op;
}

- (CKKSResultOperation*)fetchAndProcessCKChanges:(CKKSFetchBecause*)because {
    return [self fetchAndProcessCKChanges:because after:nil];
}

- (CKKSResultOperation*)fetchAndProcessCKChanges:(CKKSFetchBecause*)because after:(CKKSResultOperation*)after {
    if(!SecCKKSIsEnabled()) {
        ckksinfo("ckks", self, "Skipping fetchAndProcessCKChanges due to disabled CKKS");
        return nil;
    }

    if(after) {
        [self.zoneChangeFetcher holdFetchesUntil:after];
    }

    // We fetched some changes; try to process them!
    return [self processIncomingQueue:false after:[self.zoneChangeFetcher requestSuccessfulFetch:because]];
}

- (CKKSResultOperation*)fetchAndProcessCKChangesDueToAPNS:(CKRecordZoneNotification*)notification {
    if(!SecCKKSIsEnabled()) {
        ckksinfo("ckks", self, "Skipping fetchAndProcessCKChanges due to disabled CKKS");
        return nil;
    }

    CKKSResultOperation *fetchOp = [self.zoneChangeFetcher requestFetchDueToAPNS:notification];
    if (fetchOp == nil) {
        ckksnotice("ckks", self, "Skipping push induced processCKChanges due to zones are not ready");
        return nil;
    }

    // We fetched some changes; try to process them!
    return [self processIncomingQueue:false after:fetchOp];
}

// Lets the view know about a failed CloudKit write. If the error is "already have one of these records", it will
// store the new records and kick off the new processing
//
// Note that you need to tell this function the records you wanted to save, so it can determine what needs deletion
- (bool)_onqueueCKWriteFailed:(NSError*)ckerror attemptedRecordsChanged:(NSDictionary<CKRecordID*, CKRecord*>*)savedRecords {
    dispatch_assert_queue(self.queue);

    NSDictionary<CKRecordID*,NSError*>* partialErrors = ckerror.userInfo[CKPartialErrorsByItemIDKey];
    if([ckerror.domain isEqual:CKErrorDomain] && ckerror.code == CKErrorPartialFailure && partialErrors) {
        // Check if this error was "you're out of date"
        bool recordChanged = true;

        for(NSError* error in partialErrors.allValues) {
            if((![error.domain isEqual:CKErrorDomain]) || (error.code != CKErrorBatchRequestFailed && error.code != CKErrorServerRecordChanged && error.code != CKErrorUnknownItem)) {
                // There's an error in there that isn't CKErrorServerRecordChanged, CKErrorBatchRequestFailed, or CKErrorUnknownItem. Don't handle nicely...
                recordChanged = false;
            }
        }

        if(recordChanged) {
            ckksnotice("ckks", self, "Received a ServerRecordChanged error, attempting to update new records and delete unknown ones");

            bool updatedRecord = false;

            for(CKRecordID* recordID in partialErrors.allKeys) {
                NSError* error = partialErrors[recordID];
                if([error.domain isEqual:CKErrorDomain] && error.code == CKErrorServerRecordChanged) {
                    CKRecord* newRecord = error.userInfo[CKRecordChangedErrorServerRecordKey];
                    ckksnotice("ckks", self, "On error: updating our idea of: %@", newRecord);

                    updatedRecord |= [self _onqueueCKRecordChanged:newRecord resync:true];
                } else if([error.domain isEqual:CKErrorDomain] && error.code == CKErrorUnknownItem) {
                    CKRecord* record = savedRecords[recordID];
                    ckksnotice("ckks", self, "On error: handling an unexpected delete of: %@ %@", recordID, record);

                    updatedRecord |= [self _onqueueCKRecordDeleted:recordID recordType:record.recordType resync:true];
                }
            }

            if(updatedRecord) {
                [self processIncomingQueue:false];
                return true;
            }
        }

        // Check if this error was the CKKS server extension rejecting the write
        for(CKRecordID* recordID in partialErrors.allKeys) {
            NSError* error = partialErrors[recordID];

            NSError* underlyingError = error.userInfo[NSUnderlyingErrorKey];
            NSError* thirdLevelError = underlyingError.userInfo[NSUnderlyingErrorKey];
            ckksnotice("ckks", self, "Examining 'write failed' error: %@ %@ %@", error, underlyingError, thirdLevelError);

            if([error.domain isEqualToString:CKErrorDomain] && error.code == CKErrorServerRejectedRequest &&
               underlyingError && [underlyingError.domain isEqualToString:CKInternalErrorDomain] && underlyingError.code == CKErrorInternalPluginError &&
               thirdLevelError && [thirdLevelError.domain isEqualToString:@"CloudkitKeychainService"]) {

                if(thirdLevelError.code == CKKSServerUnexpectedSyncKeyInChain) {
                    // The server thinks the classA/C synckeys don't wrap directly the to top TLK, but we don't (otherwise, we would have fixed it).
                    // Issue a key hierarchy fetch and see what's what.
                    ckkserror("ckks", self, "CKKS Server extension has told us about %@ for record %@; requesting refetch and reprocess of key hierarchy", thirdLevelError, recordID);
                    [self _onqueueKeyStateMachineRequestFetch];

                } else if(thirdLevelError.code == CKKSServerMissingRecord) {
                    // The server is concerned that there's a missing record somewhere.
                    // Issue a key hierarchy fetch and see what's happening
                    ckkserror("ckks", self, "CKKS Server extension has told us about %@ for record %@; requesting refetch and reprocess of key hierarchy", thirdLevelError, recordID);
                    [self _onqueueKeyStateMachineRequestFetch];

                } else {
                    ckkserror("ckks", self, "CKKS Server extension has told us about %@ for record %@, but we don't currently handle this error", thirdLevelError, recordID);
                }
            }
        }
    }

    return false;
}

- (bool)_onqueueCKRecordDeleted:(CKRecordID*)recordID recordType:(NSString*)recordType resync:(bool)resync {
    dispatch_assert_queue(self.queue);

    // TODO: resync doesn't really mean much here; what does it mean for a record to be 'deleted' if you're fetching from scratch?

    if([recordType isEqual: SecCKRecordItemType]) {
        ckksinfo("ckks", self, "CloudKit notification: deleted record(%@): %@", recordType, recordID);
        NSError* error = nil;
        NSError* iqeerror = nil;
        CKKSMirrorEntry* ckme = [CKKSMirrorEntry fromDatabase: [recordID recordName] zoneID:self.zoneID error: &error];

        // Deletes always succeed, not matter the generation count
        if(ckme) {
            [ckme deleteFromDatabase:&error];

            CKKSIncomingQueueEntry* iqe = [[CKKSIncomingQueueEntry alloc] initWithCKKSItem:ckme.item action:SecCKKSActionDelete state:SecCKKSStateNew];
            [iqe saveToDatabase:&iqeerror];
            if(iqeerror) {
                ckkserror("ckks", self, "Couldn't save incoming queue entry: %@", iqeerror);
            }
        }
        ckksinfo("ckks", self, "CKKSMirrorEntry was deleted: %@ %@ error: %@", recordID, ckme, error);
        // TODO: actually pass error back up
        return (error == nil);

    } else if([recordType isEqual: SecCKRecordCurrentItemType]) {
        ckksinfo("ckks", self, "CloudKit notification: deleted current item pointer(%@): %@", recordType, recordID);
        NSError* error = nil;

        [[CKKSCurrentItemPointer tryFromDatabase:[recordID recordName] state:SecCKKSProcessedStateRemote zoneID:self.zoneID error:&error] deleteFromDatabase:&error];
        [[CKKSCurrentItemPointer fromDatabase:[recordID recordName]    state:SecCKKSProcessedStateLocal  zoneID:self.zoneID error:&error] deleteFromDatabase:&error];

        ckksinfo("ckks", self, "CKKSCurrentItemPointer was deleted: %@ error: %@", recordID, error);
        return (error == nil);

    } else if([recordType isEqual: SecCKRecordIntermediateKeyType]) {
        // TODO: handle in some interesting way
        return true;
    } else if([recordType isEqual: SecCKRecordTLKShareType]) {
        NSError* error = nil;
        ckksinfo("ckks", self, "CloudKit notification: deleted tlk share record(%@): %@", recordType, recordID);
        CKKSTLKShareRecord* share = [CKKSTLKShareRecord tryFromDatabaseFromCKRecordID:recordID error:&error];
        [share deleteFromDatabase:&error];

        if(error) {
            ckkserror("ckks", self, "CK notification: Couldn't delete deleted TLKShare: %@ %@", recordID,  error);
        }
        return (error == nil);

    } else if([recordType isEqual: SecCKRecordDeviceStateType]) {
        NSError* error = nil;
        ckksinfo("ckks", self, "CloudKit notification: deleted device state record(%@): %@", recordType, recordID);

        CKKSDeviceStateEntry* cdse = [CKKSDeviceStateEntry tryFromDatabaseFromCKRecordID:recordID error:&error];
        [cdse deleteFromDatabase: &error];
        ckksinfo("ckks", self, "CKKSCurrentItemPointer(%@) was deleted: %@ error: %@", cdse, recordID, error);

        return (error == nil);

    } else if ([recordType isEqualToString:SecCKRecordManifestType]) {
        ckksinfo("ckks", self, "CloudKit notification: deleted manifest record (%@): %@", recordType, recordID);
        
        NSError* error = nil;
        CKKSManifest* manifest = [CKKSManifest manifestForRecordName:recordID.recordName error:&error];
        if (manifest) {
            [manifest deleteFromDatabase:&error];
        }
        
        ckksinfo("ckks", self, "CKKSManifest was deleted: %@ %@ error: %@", recordID, manifest, error);
        // TODO: actually pass error back up
        return error == nil;
    }

    else {
        ckkserror("ckksfetch", self, "unknown record type: %@ %@", recordType, recordID);
        return false;
    }
}

- (bool)_onqueueCKRecordChanged:(CKRecord*)record resync:(bool)resync {
    dispatch_assert_queue(self.queue);

    @autoreleasepool {
        ckksnotice("ckksfetch", self, "Processing record modification(%@): %@", record.recordType, record);

        if([[record recordType] isEqual: SecCKRecordItemType]) {
            [self _onqueueCKRecordItemChanged:record resync:resync];
            return true;
        } else if([[record recordType] isEqual: SecCKRecordCurrentItemType]) {
            [self _onqueueCKRecordCurrentItemPointerChanged:record resync:resync];
            return true;
        } else if([[record recordType] isEqual: SecCKRecordIntermediateKeyType]) {
            [self _onqueueCKRecordKeyChanged:record resync:resync];
            return true;
        } else if ([[record recordType] isEqual: SecCKRecordTLKShareType]) {
            [self _onqueueCKRecordTLKShareChanged:record resync:resync];
            return true;
        } else if([[record recordType] isEqualToString: SecCKRecordCurrentKeyType]) {
            [self _onqueueCKRecordCurrentKeyPointerChanged:record resync:resync];
            return true;
        } else if ([[record recordType] isEqualToString:SecCKRecordManifestType]) {
            [self _onqueueCKRecordManifestChanged:record resync:resync];
            return true;
        } else if ([[record recordType] isEqualToString:SecCKRecordManifestLeafType]) {
            [self _onqueueCKRecordManifestLeafChanged:record resync:resync];
            return true;
        } else if ([[record recordType] isEqualToString:SecCKRecordDeviceStateType]) {
            [self _onqueueCKRecordDeviceStateChanged:record resync:resync];
            return true;
        } else {
            ckkserror("ckksfetch", self, "unknown record type: %@ %@", [record recordType], record);
            return false;
        }
    }
}

- (void)_onqueueCKRecordItemChanged:(CKRecord*)record resync:(bool)resync {
    dispatch_assert_queue(self.queue);

    NSError* error = nil;
    // Find if we knew about this record in the past
    bool update = false;
    CKKSMirrorEntry* ckme = [CKKSMirrorEntry tryFromDatabase: [[record recordID] recordName] zoneID:self.zoneID error:&error];

    if(error) {
        ckkserror("ckks", self, "error loading a CKKSMirrorEntry from database: %@", error);
        // TODO: quit?
    }

    if(resync) {
        if(!ckme) {
            ckkserror("ckksresync", self, "BUG: No local item matching resynced CloudKit record: %@", record);
        } else if(![ckme matchesCKRecord:record]) {
            ckkserror("ckksresync", self, "BUG: Local item doesn't match resynced CloudKit record: %@ %@", ckme, record);
        } else {
            ckksnotice("ckksresync", self, "Already know about this item record, updating anyway: %@", record.recordID);
        }
    }

    if(ckme && ckme.item && ckme.item.generationCount > [record[SecCKRecordGenerationCountKey] unsignedLongLongValue]) {
        ckkserror("ckks", self, "received a record from CloudKit with a bad generation count: %@ (%ld > %@)", ckme.uuid,
                 (long) ckme.item.generationCount,
                 record[SecCKRecordGenerationCountKey]);
        // Abort processing this record.
        return;
    }

    // If we found an old version in the database; this might be an update
    if(ckme) {
        if([ckme matchesCKRecord:record] && !resync) {
            // This is almost certainly a record we uploaded; CKFetchChanges sends them back as new records
            ckksnotice("ckks", self, "CloudKit has told us of record we already know about; skipping update");
            return;
        }

        update = true;
        // Set the CKKSMirrorEntry's fields to be whatever this record holds
        [ckme setFromCKRecord: record];
    } else {
        // Have to make a new CKKSMirrorEntry
        ckme = [[CKKSMirrorEntry alloc] initWithCKRecord: record];
    }

    [ckme saveToDatabase: &error];

    if(error) {
        ckkserror("ckks", self, "couldn't save new CKRecord to database: %@ %@", record, error);
    } else {
        ckksdebug("ckks", self, "CKKSMirrorEntry was created: %@", ckme);
    }

    NSError* iqeerror = nil;
    CKKSIncomingQueueEntry* iqe = [[CKKSIncomingQueueEntry alloc] initWithCKKSItem:ckme.item
                                                                            action:(update ? SecCKKSActionModify : SecCKKSActionAdd)
                                                                             state:SecCKKSStateNew];
    [iqe saveToDatabase:&iqeerror];
    if(iqeerror) {
        ckkserror("ckks", self, "Couldn't save modified incoming queue entry: %@", iqeerror);
    } else {
        ckksdebug("ckks", self, "CKKSIncomingQueueEntry was created: %@", iqe);
    }

    // A remote change has occured for this record. Delete any pending local changes; they will be overwritten.
    CKKSOutgoingQueueEntry* oqe = [CKKSOutgoingQueueEntry tryFromDatabase:ckme.uuid state: SecCKKSStateNew zoneID:self.zoneID error: &error];
    if(error) {
        ckkserror("ckks", self, "Couldn't load OutgoingQueueEntry: %@", error);
    }
    if(oqe) {
        [self _onqueueChangeOutgoingQueueEntry:oqe toState:SecCKKSStateDeleted error:&error];
    }

    // Reencryptions are pending changes too
    oqe = [CKKSOutgoingQueueEntry tryFromDatabase:ckme.uuid state: SecCKKSStateReencrypt zoneID:self.zoneID error: &error];
    if(error) {
        ckkserror("ckks", self, "Couldn't load reencrypted OutgoingQueueEntry: %@", error);
    }
    if(oqe) {
        [oqe deleteFromDatabase:&error];
        if(error) {
            ckkserror("ckks", self, "Couldn't delete reencrypted oqe(%@): %@", oqe, error);
        }
    }
}

- (void)_onqueueCKRecordKeyChanged:(CKRecord*)record resync:(bool)resync {
    dispatch_assert_queue(self.queue);

    NSError* error = nil;

    if(resync) {
        NSError* resyncerror = nil;

        CKKSKey* key = [CKKSKey tryFromDatabaseAnyState:record.recordID.recordName zoneID:self.zoneID error:&resyncerror];
        if(resyncerror) {
            ckkserror("ckksresync", self, "error loading key: %@", resyncerror);
        }
        if(!key) {
            ckkserror("ckksresync", self, "BUG: No sync key matching resynced CloudKit record: %@", record);
        } else if(![key matchesCKRecord:record]) {
            ckkserror("ckksresync", self, "BUG: Local sync key doesn't match resynced CloudKit record(s): %@ %@", key, record);
        } else {
            ckksnotice("ckksresync", self, "Already know about this sync key, skipping update: %@", record);
            return;
        }
    }

    CKKSKey* remotekey = [[CKKSKey alloc] initWithCKRecord: record];

    // Do we already know about this key?
    CKKSKey* possibleLocalKey = [CKKSKey tryFromDatabase:remotekey.uuid zoneID:self.zoneID error:&error];
    if(error) {
        ckkserror("ckkskey", self, "Error findibg exsiting local key for %@: %@", remotekey, error);
        // Go on, assuming there isn't a local key
    } else if(possibleLocalKey && [possibleLocalKey matchesCKRecord:record]) {
        // Okay, nothing new here. Update the CKRecord and move on.
        // Note: If the new record doesn't match the local copy, we have to go through the whole dance below
        possibleLocalKey.storedCKRecord = record;
        [possibleLocalKey saveToDatabase:&error];

        if(error) {
            ckkserror("ckkskey", self, "Couldn't update existing key: %@: %@", possibleLocalKey, error);
        }
        return;
    }

    // Drop into the synckeys table as a 'remote' key, then ask for a rekey operation.
    remotekey.state = SecCKKSProcessedStateRemote;
    remotekey.currentkey = false;

    [remotekey saveToDatabase:&error];
    if(error) {
        ckkserror("ckkskey", self, "Couldn't save key record to database: %@: %@", remotekey, error);
        ckksinfo("ckkskey", self, "CKRecord was %@", record);
    }

    // We've saved a new key in the database; trigger a rekey operation.
    [self _onqueueKeyStateMachineRequestProcess];
}

- (void)_onqueueCKRecordTLKShareChanged:(CKRecord*)record resync:(bool)resync {
    dispatch_assert_queue(self.queue);

    NSError* error = nil;
    if(resync) {
        // TODO fill in
    }

    // CKKSTLKShares get saved with no modification
    CKKSTLKShareRecord* share = [[CKKSTLKShareRecord alloc] initWithCKRecord:record];
    [share saveToDatabase:&error];
    if(error) {
        ckkserror("ckksshare", self, "Couldn't save new TLK share to database: %@ %@", share, error);
    }

    [self _onqueueKeyStateMachineRequestProcess];
}

- (void)_onqueueCKRecordCurrentKeyPointerChanged:(CKRecord*)record resync:(bool)resync {
    dispatch_assert_queue(self.queue);

    // Pull out the old CKP, if it exists
    NSError* ckperror = nil;
    CKKSCurrentKeyPointer* oldckp = [CKKSCurrentKeyPointer tryFromDatabase:((CKKSKeyClass*) record.recordID.recordName) zoneID:self.zoneID error:&ckperror];
    if(ckperror) {
        ckkserror("ckkskey", self, "error loading ckp: %@", ckperror);
    }

    if(resync) {
        if(!oldckp) {
            ckkserror("ckksresync", self, "BUG: No current key pointer matching resynced CloudKit record: %@", record);
        } else if(![oldckp matchesCKRecord:record]) {
            ckkserror("ckksresync", self, "BUG: Local current key pointer doesn't match resynced CloudKit record: %@ %@", oldckp, record);
        } else {
            ckksnotice("ckksresync", self, "Current key pointer has 'changed', but it matches our local copy: %@", record);
        }
    }

    NSError* error = nil;
    CKKSCurrentKeyPointer* currentkey = [[CKKSCurrentKeyPointer alloc] initWithCKRecord: record];

    [currentkey saveToDatabase: &error];
    if(error) {
        ckkserror("ckkskey", self, "Couldn't save current key pointer to database: %@: %@", currentkey, error);
        ckksinfo("ckkskey", self, "CKRecord was %@", record);
    }

    if([oldckp matchesCKRecord:record]) {
        ckksnotice("ckkskey", self, "Current key pointer modification doesn't change anything interesting; skipping reprocess: %@", record);
    } else {
        // We've saved a new key in the database; trigger a rekey operation.
        [self _onqueueKeyStateMachineRequestProcess];
    }
}

- (void)_onqueueCKRecordCurrentItemPointerChanged:(CKRecord*)record resync:(bool)resync {
    dispatch_assert_queue(self.queue);

    if(resync) {
        NSError* ciperror = nil;
        CKKSCurrentItemPointer* localcip  = [CKKSCurrentItemPointer tryFromDatabase:record.recordID.recordName state:SecCKKSProcessedStateLocal  zoneID:self.zoneID error:&ciperror];
        CKKSCurrentItemPointer* remotecip = [CKKSCurrentItemPointer tryFromDatabase:record.recordID.recordName state:SecCKKSProcessedStateRemote zoneID:self.zoneID error:&ciperror];
        if(ciperror) {
            ckkserror("ckksresync", self, "error loading cip: %@", ciperror);
        }
        if(!(localcip || remotecip)) {
            ckkserror("ckksresync", self, "BUG: No current item pointer matching resynced CloudKit record: %@", record);
        } else if(! ([localcip matchesCKRecord:record] || [remotecip matchesCKRecord:record]) ) {
            ckkserror("ckksresync", self, "BUG: Local current item pointer doesn't match resynced CloudKit record(s): %@ %@ %@", localcip, remotecip, record);
        } else {
            ckksnotice("ckksresync", self, "Already know about this current item pointer, skipping update: %@", record);
            return;
        }
    }

    NSError* error = nil;
    CKKSCurrentItemPointer* cip = [[CKKSCurrentItemPointer alloc] initWithCKRecord: record];
    cip.state = SecCKKSProcessedStateRemote;

    [cip saveToDatabase: &error];
    if(error) {
        ckkserror("currentitem", self, "Couldn't save current item pointer to database: %@: %@ %@", cip, error, record);
    }
}

- (void)_onqueueCKRecordManifestChanged:(CKRecord*)record resync:(bool)resync
{
    NSError* error = nil;
    CKKSPendingManifest* manifest = [[CKKSPendingManifest alloc] initWithCKRecord:record];
    [manifest saveToDatabase:&error];
    if (error) {
        ckkserror("CKKS", self, "Failed to save fetched manifest record to database: %@: %@", manifest, error);
        ckksinfo("CKKS", self, "manifest CKRecord was %@", record);
    }
}

- (void)_onqueueCKRecordManifestLeafChanged:(CKRecord*)record resync:(bool)resync
{
    NSError* error = nil;
    CKKSManifestLeafRecord* manifestLeaf = [[CKKSManifestPendingLeafRecord alloc] initWithCKRecord:record];
    [manifestLeaf saveToDatabase:&error];
    if (error) {
        ckkserror("CKKS", self, "Failed to save fetched manifest leaf record to database: %@: %@", manifestLeaf, error);
        ckksinfo("CKKS", self, "manifest leaf CKRecord was %@", record);
    }
}

- (void)_onqueueCKRecordDeviceStateChanged:(CKRecord*)record resync:(bool)resync {
    if(resync) {
        NSError* dserror = nil;
        CKKSDeviceStateEntry* cdse  = [CKKSDeviceStateEntry tryFromDatabase:record.recordID.recordName zoneID:self.zoneID error:&dserror];
        if(dserror) {
            ckkserror("ckksresync", self, "error loading cdse: %@", dserror);
        }
        if(!cdse) {
            ckkserror("ckksresync", self, "BUG: No current device state entry matching resynced CloudKit record: %@", record);
        } else if(![cdse matchesCKRecord:record]) {
            ckkserror("ckksresync", self, "BUG: Local current device state entry doesn't match resynced CloudKit record(s): %@ %@", cdse, record);
        } else {
            ckksnotice("ckksresync", self, "Already know about this current item pointer, skipping update: %@", record);
            return;
        }
    }

    NSError* error = nil;
    CKKSDeviceStateEntry* cdse = [[CKKSDeviceStateEntry alloc] initWithCKRecord:record];
    [cdse saveToDatabase:&error];
    if (error) {
        ckkserror("ckksdevice", self, "Failed to save device record to database: %@: %@ %@", cdse, error, record);
    }
}

- (bool)_onqueueResetAllInflightOQE:(NSError**)error {
    NSError* localError = nil;

    while(true) {
        NSArray<CKKSOutgoingQueueEntry*> * inflightQueueEntries = [CKKSOutgoingQueueEntry fetch:SecCKKSOutgoingQueueItemsAtOnce
                                                                                          state:SecCKKSStateInFlight
                                                                                         zoneID:self.zoneID
                                                                                          error:&localError];

        if(localError != nil) {
            ckkserror("ckks", self, "Error finding inflight outgoing queue records: %@", localError);
            if(error) {
                *error = localError;
            }
            return false;
        }

        if([inflightQueueEntries count] == 0u) {
            break;
        }

        for(CKKSOutgoingQueueEntry* oqe in inflightQueueEntries) {
            [self _onqueueChangeOutgoingQueueEntry:oqe toState:SecCKKSStateNew error:&localError];

            if(localError) {
                ckkserror("ckks", self, "Error fixing up inflight OQE(%@): %@", oqe, localError);
                if(error) {
                    *error = localError;
                }
                return false;
            }
        }
    }

    return true;
}

- (bool)_onqueueChangeOutgoingQueueEntry: (CKKSOutgoingQueueEntry*) oqe toState: (NSString*) state error: (NSError* __autoreleasing*) error {
    dispatch_assert_queue(self.queue);

    NSError* localerror = nil;

    if([state isEqualToString: SecCKKSStateDeleted]) {
        // Hurray, this must be a success
        SecBoolNSErrorCallback callback = self.pendingSyncCallbacks[oqe.uuid];
        if(callback) {
            callback(true, nil);
            self.pendingSyncCallbacks[oqe.uuid] = nil;
        }

        [oqe deleteFromDatabase: &localerror];
        if(localerror) {
            ckkserror("ckks", self, "Couldn't delete %@: %@", oqe, localerror);
        }

    } else if([oqe.state isEqualToString:SecCKKSStateInFlight] && [state isEqualToString:SecCKKSStateNew]) {
        // An in-flight OQE is moving to new? See if it's been superceded
        CKKSOutgoingQueueEntry* newOQE = [CKKSOutgoingQueueEntry tryFromDatabase:oqe.uuid state:SecCKKSStateNew zoneID:self.zoneID error:&localerror];
        if(localerror) {
            ckkserror("ckksoutgoing", self, "Couldn't fetch an overwriting OQE, assuming one doesn't exist: %@", localerror);
            newOQE = nil;
        }

        if(newOQE) {
            ckksnotice("ckksoutgoing", self, "New modification has come in behind inflight %@; dropping failed change", oqe);
            // recurse for that lovely code reuse
            [self _onqueueChangeOutgoingQueueEntry:oqe toState:SecCKKSStateDeleted error:&localerror];
            if(localerror) {
                ckkserror("ckksoutgoing", self, "Couldn't delete in-flight OQE: %@", localerror);
                if(error) {
                    *error = localerror;
                }
            }
        } else {
            oqe.state = state;
            [oqe saveToDatabase: &localerror];
            if(localerror) {
                ckkserror("ckks", self, "Couldn't save %@ as %@: %@", oqe, state, localerror);
            }
        }

    } else {
        oqe.state = state;
        [oqe saveToDatabase: &localerror];
        if(localerror) {
            ckkserror("ckks", self, "Couldn't save %@ as %@: %@", oqe, state, localerror);
        }
    }

    if(error && localerror) {
        *error = localerror;
    }
    return localerror == nil;
}

- (bool)_onqueueErrorOutgoingQueueEntry: (CKKSOutgoingQueueEntry*) oqe itemError: (NSError*) itemError error: (NSError* __autoreleasing*) error {
    dispatch_assert_queue(self.queue);

    SecBoolNSErrorCallback callback = self.pendingSyncCallbacks[oqe.uuid];
    if(callback) {
        callback(false, itemError);
        self.pendingSyncCallbacks[oqe.uuid] = nil;
    }
    NSError* localerror = nil;

    // Now, delete the OQE: it's never coming back
    [oqe deleteFromDatabase:&localerror];
    if(localerror) {
        ckkserror("ckks", self, "Couldn't delete %@ (due to error %@): %@", oqe, itemError, localerror);
    }

    if(error && localerror) {
        *error = localerror;
    }
    return localerror == nil;
}

- (bool)_onqueueUpdateLatestManifestWithError:(NSError**)error
{
    dispatch_assert_queue(self.queue);
    CKKSManifest* manifest = [CKKSManifest latestTrustedManifestForZone:self.zoneName error:error];
    if (manifest) {
        self.latestManifest = manifest;
        return true;
    }
    else {
        return false;
    }
}

- (bool)_onqueueWithAccountKeysCheckTLK:(CKKSKey*)proposedTLK error:(NSError* __autoreleasing *)error {
    dispatch_assert_queue(self.queue);
    // First, if we have a local identity, check for any TLK shares
    NSError* localerror = nil;

    if(![proposedTLK wrapsSelf]) {
        localerror = [NSError errorWithDomain:CKKSErrorDomain code:CKKSKeyNotSelfWrapped description:[NSString stringWithFormat:@"Potential TLK %@ doesn't wrap itself: %@", proposedTLK, proposedTLK.parentKeyUUID] underlying:NULL];
        ckkserror("ckksshare", self, "%@", localerror);
        if (error) {
            *error = localerror;
        }
    } else {
        bool tlkShares = [self _onqueueWithAccountKeysCheckTLKFromShares:proposedTLK error:&localerror];
        // We only want to error out if a positive error occurred. "No shares" is okay.
        if(!tlkShares || localerror) {
            bool noTrustedTLKShares = [localerror.domain isEqualToString:CKKSErrorDomain] && localerror.code == CKKSNoTrustedTLKShares;
            bool noSelfPeer = [localerror.domain isEqualToString:CKKSErrorDomain] && localerror.code == CKKSNoEncryptionKey;
            bool noTrust = [localerror.domain isEqualToString:CKKSErrorDomain] && localerror.code == CKKSLackingTrust;

            // If this error was something worse than 'couldn't unwrap for reasons including there not being data', report it
            if(!(noTrustedTLKShares || noSelfPeer || noTrust)) {
                if(error) {
                    *error = localerror;
                }
                ckkserror("ckksshare", self, "Errored unwrapping TLK with TLKShares: %@", localerror);
                return false;
            } else {
                ckkserror("ckksshare", self, "Non-fatal error unwrapping TLK with TLKShares: %@", localerror);
            }
        }
    }

    if([proposedTLK loadKeyMaterialFromKeychain:error]) {
        // Hurray!
        return true;
    } else {
        return false;
    }
}

// This version only examines if this TLK is recoverable from TLK shares
- (bool)_onqueueWithAccountKeysCheckTLKFromShares:(CKKSKey*)proposedTLK error:(NSError* __autoreleasing *)error {
    // But being recoverable from any trust set is okay
    NSError* localerror = nil;

    if(self.currentTrustStates.count == 0u) {
        if(error) {
            *error = [NSError errorWithDomain:CKKSErrorDomain
                                         code:CKKSLackingTrust
                                  description:@"No current trust states; can't check TLK"];
        }
        return false;
    }

    for(CKKSPeerProviderState* trustState in self.currentTrustStates) {
        ckkserror("ckksshare", self, "Checking TLK from trust state %@", trustState);
        bool recovered = [self _onqueueWithAccountKeysWithPeers:trustState
                                                       checkTLK:proposedTLK
                                                          error:&localerror];

        if(recovered) {
            ckkserror("ckksshare", self, "Recovered the TLK");
            return true;
        }

        ckkserror("ckksshare", self, "Unable to recover TLK from trust set: %@", localerror);
    }

    // Only report the last error
    if(error && localerror) {
        *error = localerror;
    }
    return false;
}

- (bool)_onqueueWithAccountKeysWithPeers:(CKKSPeerProviderState*)trustState
                                checkTLK:(CKKSKey*)proposedTLK
                                  error:(NSError* __autoreleasing *)error
{
    NSError* localerror = NULL;
    if(!trustState.currentSelfPeers.currentSelf || trustState.currentSelfPeersError) {
        ckkserror("ckksshare", self, "Don't have self peers for %@: %@", trustState.peerProviderID, trustState.currentSelfPeersError);
        if(error) {
            if([self.lockStateTracker isLockedError:trustState.currentSelfPeersError]) {
                // Locked error should propagate
                *error = trustState.currentSelfPeersError;
            } else {
                *error = [NSError errorWithDomain:CKKSErrorDomain
                                             code:CKKSNoEncryptionKey
                                      description:@"No current self peer"
                                       underlying:trustState.currentSelfPeersError];
            }
        }
        return false;
    }

    if(!trustState.currentTrustedPeers || trustState.currentTrustedPeersError) {
        ckkserror("ckksshare", self, "Don't have trusted peers: %@", trustState.currentTrustedPeersError);
        if(error) {
            *error = [NSError errorWithDomain:CKKSErrorDomain
                                         code:CKKSNoPeersAvailable
                                  description:@"No trusted peers"
                                   underlying:trustState.currentTrustedPeersError];
        }
        return false;
    }

    NSError* lastShareError = nil;

    for(id<CKKSSelfPeer> selfPeer in trustState.currentSelfPeers.allSelves) {
        NSArray<CKKSTLKShareRecord*>* possibleShares = [CKKSTLKShareRecord allFor:selfPeer.peerID
                                                              keyUUID:proposedTLK.uuid
                                                               zoneID:self.zoneID
                                                                error:&localerror];
        if(localerror) {
            ckkserror("ckksshare", self, "Error fetching CKKSTLKShares for %@: %@", selfPeer, localerror);
        }

        if(possibleShares.count == 0) {
            ckksnotice("ckksshare", self, "No CKKSTLKShares to %@ for %@", selfPeer, proposedTLK);
            continue;
        }

        for(CKKSTLKShareRecord* possibleShare in possibleShares) {
            NSError* possibleShareError = nil;
            ckksnotice("ckksshare", self, "Checking possible TLK share %@ as %@", possibleShare, selfPeer);

            CKKSKey* possibleKey = [possibleShare recoverTLK:selfPeer
                                                trustedPeers:trustState.currentTrustedPeers
                                                       error:&possibleShareError];

            if(possibleShareError) {
                ckkserror("ckksshare", self, "Unable to unwrap TLKShare(%@) as %@: %@",
                          possibleShare, selfPeer, possibleShareError);
                ckkserror("ckksshare", self, "Current trust set: %@", trustState.currentTrustedPeers);
                lastShareError = possibleShareError;
                continue;
            }

            bool result = [proposedTLK trySelfWrappedKeyCandidate:possibleKey.aessivkey error:&possibleShareError];
            if(possibleShareError) {
                ckkserror("ckksshare", self, "Unwrapped TLKShare(%@) does not unwrap proposed TLK(%@) as %@: %@",
                          possibleShare, proposedTLK, trustState.currentSelfPeers.currentSelf, possibleShareError);
                lastShareError = possibleShareError;
                continue;
            }

            if(result) {
                ckksnotice("ckksshare", self, "TLKShare(%@) unlocked TLK(%@) as %@",
                           possibleShare, proposedTLK, selfPeer);

                // The proposed TLK is trusted key material. Persist it as a "trusted" key.
                [proposedTLK saveKeyMaterialToKeychain:true error:&possibleShareError];
                if(possibleShareError) {
                    ckkserror("ckksshare", self, "Couldn't store the new TLK(%@) to the keychain: %@", proposedTLK, possibleShareError);
                    if(error) {
                        *error = possibleShareError;
                    }
                    return false;
                }

                return true;
            }
        }
    }

    if(error) {
        *error = [NSError errorWithDomain:CKKSErrorDomain
                                     code:CKKSNoTrustedTLKShares
                              description:[NSString stringWithFormat:@"No trusted TLKShares for %@", proposedTLK]
                               underlying:lastShareError];
    }
    return false;
}

- (bool)dispatchSyncWithConnection:(SecDbConnectionRef _Nonnull)dbconn block:(bool (^)(void))block {
    CFErrorRef cferror = NULL;

    // Take the DB transaction, then get on the local queue.
    // In the case of exclusive DB transactions, we don't really _need_ the local queue, but, it's here for future use.
    bool ret = kc_transaction_type(dbconn, kSecDbExclusiveRemoteCKKSTransactionType, &cferror, ^bool{
        __block bool ok = false;

        dispatch_sync(self.queue, ^{
            ok = block();
        });

        return ok;
    });

    if(cferror) {
        ckkserror("ckks", self, "error doing database transaction, major problems ahead: %@", cferror);
    }
    return ret;
}

- (void)dispatchSync: (bool (^)(void)) block {
    // important enough to block this thread. Must get a connection first, though!

    // Please don't jetsam us...
    os_transaction_t transaction = os_transaction_create([[NSString stringWithFormat:@"com.apple.securityd.ckks.%@", self.zoneName] UTF8String]);

    CFErrorRef cferror = NULL;
    kc_with_dbt(true, &cferror, ^bool (SecDbConnectionRef dbt) {
        return [self dispatchSyncWithConnection:dbt block:block];
    });
    if(cferror) {
        ckkserror("ckks", self, "error getting database connection, major problems ahead: %@", cferror);
    }

    (void)transaction;
}

- (void)dispatchSyncWithAccountKeys:(bool (^)(void))block
{
    [self dispatchSyncWithPeerProviders:self.currentPeerProviders override:false block:block];
}

- (void)dispatchSyncWithPeerProviders:(NSArray<id<CKKSPeerProvider>>*)peerProviders
                             override:(bool)overridePeerProviders
                                block:(bool (^)(void))block
{
    NSArray<id<CKKSPeerProvider>>* actualPeerProviders = overridePeerProviders ? peerProviders : self.currentPeerProviders;
    NSMutableArray<CKKSPeerProviderState*>* trustStates = [NSMutableArray array];

    for(id<CKKSPeerProvider> provider in actualPeerProviders) {
        ckksnotice("ckks", self, "Fetching account keys for provider %@", provider);
        [trustStates addObject:provider.currentState];
    }

    [self dispatchSync:^bool{
        if(overridePeerProviders) {
            self.currentPeerProviders = peerProviders;
        }
        self.currentTrustStates = trustStates;

        bool result = block();

        // Forget the peers; they might have class A key material
        NSMutableArray<CKKSPeerProviderState*>* noTrustStates = [NSMutableArray array];
        for(id<CKKSPeerProvider> provider in peerProviders) {
            (void)provider;
            [noTrustStates addObject:[CKKSPeerProviderState noPeersState:provider]];
        }
        self.currentTrustStates = noTrustStates;

        return result;
    }];
}

#pragma mark - CKKSZoneUpdateReceiver

- (void)notifyZoneChange: (CKRecordZoneNotification*) notification {
    ckksnotice("ckks", self, "received a zone change notification for %@ %@", self, notification);

    [self fetchAndProcessCKChangesDueToAPNS:notification];
}

- (void)superHandleCKLogin {
    [super handleCKLogin];
}

- (void)handleCKLogin {
    ckksnotice("ckks", self, "received a notification of CK login");
    if(!SecCKKSIsEnabled()) {
        ckksnotice("ckks", self, "Skipping CloudKit initialization due to disabled CKKS");
        return;
    }

    WEAKIFY(self);
    CKKSResultOperation* login = [CKKSResultOperation named:@"ckks-login" withBlock:^{
        STRONGIFY(self);

        [self dispatchSyncWithAccountKeys:^bool{
            [self superHandleCKLogin];

            // Reset key hierarchy state machine to initializing
            [self _onqueueAdvanceKeyStateMachineToState:SecCKKSZoneKeyStateInitializing withError:nil];
            return true;
        }];

        // Change our condition variables to reflect that we think we're logged in
        self.loggedOut = [[CKKSCondition alloc] initToChain:self.loggedOut];
        [self.loggedIn fulfill];
        [self.accountStateKnown fulfill];
    }];

    [self scheduleAccountStatusOperation:login];
}

- (void)superHandleCKLogout {
    [super handleCKLogout];
}

- (void)handleCKLogout {
    WEAKIFY(self);
    CKKSResultOperation* logout = [CKKSResultOperation named:@"ckks-logout" withBlock: ^{
        STRONGIFY(self);
        if(!self) {
            return;
        }
        [self dispatchSync:^bool {
            ckksnotice("ckks", self, "received a notification of CK logout");
            [self superHandleCKLogout];

            NSError* error = nil;
            [self _onqueueResetLocalData: &error];
            if(error) {
                ckkserror("ckks", self, "error while resetting local data: %@", error);
            }

            [self _onqueueAdvanceKeyStateMachineToState:SecCKKSZoneKeyStateLoggedOut withError:nil];

            self.loggedIn = [[CKKSCondition alloc] initToChain: self.loggedIn];
            [self.loggedOut fulfill];
            [self.accountStateKnown fulfill];

            // Tell all pending sync clients that we don't expect to ever sync
            for(NSString* callbackUUID in self.pendingSyncCallbacks.allKeys) {
                [self callSyncCallbackWithErrorNoAccount:self.pendingSyncCallbacks[callbackUUID]];
                self.pendingSyncCallbacks[callbackUUID] = nil;
            }

            return true;
        }];
    }];

    [self scheduleAccountStatusOperation: logout];
}

- (void)callSyncCallbackWithErrorNoAccount:(SecBoolNSErrorCallback)syncCallback {
    CKKSAccountStatus accountStatus = self.accountStatus;
    dispatch_async(self.queue, ^{
        syncCallback(false, [NSError errorWithDomain:@"securityd"
                                                code:errSecNotLoggedIn
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat: @"No iCloud account available(%d); item is not expected to sync", (int)accountStatus]}]);
    });
}

#pragma mark - Trust operations

- (void)beginTrustedOperation:(NSArray<id<CKKSPeerProvider>>*)peerProviders
             suggestTLKUpload:(CKKSNearFutureScheduler*)suggestTLKUpload
{
    for(id<CKKSPeerProvider> peerProvider in peerProviders) {
        [peerProvider registerForPeerChangeUpdates:self];
    }

    [self.launch addEvent:@"beginTrusted"];

    [self dispatchSyncWithPeerProviders:peerProviders override:true block:^bool {
        ckksnotice("ckkstrust", self, "Beginning trusted operation");
        CKKSAccountStatus oldTrustStatus = self.trustStatus;

        self.suggestTLKUpload = suggestTLKUpload;

        self.trustStatus = CKKSAccountStatusAvailable;
        if(self.trustDependency) {
            [self scheduleOperation: self.trustDependency];
            self.trustDependency = nil;
        }
        [self _onqueueAdvanceKeyStateMachineToState:nil withError:nil];

        if(oldTrustStatus == CKKSAccountStatusNoAccount) {
            ckksnotice("ckkstrust", self, "Moving from an untrusted status; we need to process incoming queue and scan for any new items");

            // Next, try to process them (replacing local entries)
            CKKSIncomingQueueOperation* initialProcess = [self processIncomingQueue:true after:nil];
            initialProcess.name = @"initial-process-incoming-queue";

            // If all that succeeds, iterate through all keychain items and find the ones which need to be uploaded
            self.initialScanOperation = [self scanLocalItems:@"newly-trusted-scan"
                                            ckoperationGroup:nil
                                                       after:initialProcess];
        }

        return true;
    }];
}

- (void)endTrustedOperation
{
    [self.launch addEvent:@"endTrusted"];

    [self dispatchSyncWithPeerProviders:nil override:true block:^bool {
        ckksnotice("ckkstrust", self, "Ending trusted operation");

        self.suggestTLKUpload = nil;

        self.trustStatus = CKKSAccountStatusNoAccount;
        if(!self.trustDependency) {
            self.trustDependency = [CKKSResultOperation named:@"wait-for-trust" withBlock:^{}];
        }
        [self _onqueueAdvanceKeyStateMachineToState:nil withError:nil];
        return true;
    }];
}

#pragma mark - CKKSChangeFetcherClient

- (BOOL)zoneIsReadyForFetching
{
    __block BOOL ready = NO;

    [self dispatchSync: ^bool {
        ready = (bool)[self _onQueueZoneIsReadyForFetching];
        return ready;
    }];

    return ready;
}

- (BOOL)_onQueueZoneIsReadyForFetching
{
    if(self.accountStatus != CKKSAccountStatusAvailable) {
        ckksnotice("ckksfetch", self, "Not participating in fetch: not logged in");
        return NO;
    }

    if(!self.zoneCreated) {
        ckksnotice("ckksfetch", self, "Not participating in fetch: zone not created yet");
        return NO;
    }
    return YES;
}

- (CKKSCloudKitFetchRequest*)participateInFetch
{
    __block CKKSCloudKitFetchRequest* request = [[CKKSCloudKitFetchRequest alloc] init];

    [self dispatchSync: ^bool {
        if (![self _onQueueZoneIsReadyForFetching]) {
            ckksnotice("ckksfetch", self, "skipping fetch since zones are not ready");
            return false;
        }

        request.participateInFetch = true;
        [self.launch addEvent:@"fetch"];

        if([self.keyHierarchyState isEqualToString:SecCKKSZoneKeyStateNeedFullRefetch]) {
            // We want to return a nil change tag (to force a resync)
            ckksnotice("ckksfetch", self, "Beginning refetch");
            request.changeToken = nil;
            request.resync = true;
        } else {
            CKKSZoneStateEntry* ckse = [CKKSZoneStateEntry state:self.zoneName];
            if(!ckse) {
                ckkserror("ckksfetch", self, "couldn't fetch zone change token for %@", self.zoneName);
                return false;
            }
            request.changeToken = ckse.changeToken;
        }
        return true;
    }];

    if (request.changeToken == nil) {
        self.launch.firstLaunch = true;
    }

    return request;
}

- (void)changesFetched:(NSArray<CKRecord*>*)changedRecords
      deletedRecordIDs:(NSArray<CKKSCloudKitDeletion*>*)deletedRecords
        newChangeToken:(CKServerChangeToken*)newChangeToken
            moreComing:(BOOL)moreComing
                resync:(BOOL)resync
{
    [self.launch addEvent:@"changes-fetched"];

    [self dispatchSyncWithAccountKeys:^bool{
        for (CKRecord* record in changedRecords) {
            [self _onqueueCKRecordChanged:record resync:resync];
        }

        for (CKKSCloudKitDeletion* deletion in deletedRecords) {
            [self _onqueueCKRecordDeleted:deletion.recordID recordType:deletion.recordType resync:resync];
        }

        NSError* error = nil;
        if(resync) {
            // If we're performing a resync, we need to keep track of everything that's actively in
            // CloudKit during the fetch, (so that we can find anything that's on-disk and not in CloudKit).
            // Please note that if, during a resync, the fetch errors, we won't be notified. If a record is in
            // the first refetch but not the second, it'll be added to our set, and the second resync will not
            // delete the record (which is a consistency violation, but only with actively changing records).
            // A third resync should correctly delete that record.

            if(self.resyncRecordsSeen == nil) {
                self.resyncRecordsSeen = [NSMutableSet set];
            }
            for(CKRecord* r in changedRecords) {
                [self.resyncRecordsSeen addObject:r.recordID.recordName];
            }

            // Is there More Coming? If not, self.resyncRecordsSeen contains everything in CloudKit. Inspect for anything extra!
            if(moreComing) {
                ckksnotice("ckksresync", self, "In a resync, but there's More Coming. Waiting to scan for extra items.");

            } else {
                // Scan through all CKMirrorEntries and determine if any exist that CloudKit didn't tell us about
                ckksnotice("ckksresync", self, "Comparing local UUIDs against the CloudKit list");
                NSMutableArray<NSString*>* uuids = [[CKKSMirrorEntry allUUIDs:self.zoneID error:&error] mutableCopy];

                for(NSString* uuid in uuids) {
                    if([self.resyncRecordsSeen containsObject:uuid]) {
                        ckksnotice("ckksresync", self, "UUID %@ is still in CloudKit; carry on.", uuid);
                    } else {
                        CKKSMirrorEntry* ckme = [CKKSMirrorEntry tryFromDatabase:uuid zoneID:self.zoneID error:&error];
                        if(error != nil) {
                            ckkserror("ckksresync", self, "Couldn't read an item from the database, but it used to be there: %@ %@", uuid, error);
                            continue;
                        }
                        if(!ckme) {
                            ckkserror("ckksresync", self, "Couldn't read ckme(%@) from database; continuing", uuid);
                            continue;
                        }

                        ckkserror("ckksresync", self, "BUG: Local item %@ not found in CloudKit, deleting", uuid);
                        [self _onqueueCKRecordDeleted:ckme.item.storedCKRecord.recordID recordType:ckme.item.storedCKRecord.recordType resync:resync];
                    }
                }

                // Now that we've inspected resyncRecordsSeen, reset it for the next time through
                self.resyncRecordsSeen = nil;
            }
        }

        CKKSZoneStateEntry* state = [CKKSZoneStateEntry state:self.zoneName];
        state.lastFetchTime = [NSDate date]; // The last fetch happened right now!
        state.changeToken = newChangeToken;
        state.moreRecordsInCloudKit = moreComing;
        [state saveToDatabase:&error];
        if(error) {
            ckkserror("ckksfetch", self, "Couldn't save new server change token: %@", error);
        }

        if(!moreComing) {
            // Might as well kick off a IQO!
            [self processIncomingQueue:false];
            ckksnotice("ckksfetch", self, "Beginning incoming processing for %@", self.zoneID);
        }

        ckksnotice("ckksfetch", self, "Finished processing changes for %@", self.zoneID);

        return true;
    }];
}

- (bool)ckErrorOrPartialError:(NSError *)error isError:(CKErrorCode)errorCode
{
    if((error.code == errorCode) && [error.domain isEqualToString:CKErrorDomain]) {
        return true;
    } else if((error.code == CKErrorPartialFailure) && [error.domain isEqualToString:CKErrorDomain]) {
        NSDictionary* partialErrors = error.userInfo[CKPartialErrorsByItemIDKey];

        NSError* partialError = partialErrors[self.zoneID];
        if ((partialError.code == errorCode) && [partialError.domain isEqualToString:CKErrorDomain]) {
            return true;
        }
    }
    return false;
}

- (bool)shouldRetryAfterFetchError:(NSError*)error {

    bool isChangeTokenExpiredError = [self ckErrorOrPartialError:error isError:CKErrorChangeTokenExpired];
    if(isChangeTokenExpiredError) {
        ckkserror("ckks", self, "Received notice that our change token is out of date (for %@). Resetting local data...", self.zoneID);

        // This is a bit scary: we might confuse some poor key hierarchy state machine operation. But, if a key state machine
        // operation is waiting for a successful fetch, we need to do this reset
        [self dispatchSyncWithAccountKeys:^bool{
            NSError* error = nil;
            [self _onqueueResetLocalData:&error];

            // We need to rescan the local keychain once we return to a good state
            self.droppedItems = true;

            if(error) {
                ckksnotice("ckksreset", self, "CloudKit-inspired local reset of %@ ended with error: %@", self.zoneID, error);
            } else {
                ckksnotice("ckksreset", self, "CloudKit-inspired local reset of %@ ended successfully", self.zoneID);
            }

            // If we're in the middle of a fetch for the key state, then the retried fetch (which should succeed) will be sufficient to progress
            // Otherwise, we need to poke the key hierarchy state machine: all of its data is gone
            if(![self.keyHierarchyState isEqualToString:SecCKKSZoneKeyStateFetch]) {
                [self _onqueueKeyStateMachineRequestFetch];
            }

            return true;
        }];

        return true;
    }

    bool isDeletedZoneError = [self ckErrorOrPartialError:error isError:CKErrorZoneNotFound];
    if(isDeletedZoneError) {
        ckkserror("ckks", self, "Received notice that our zone(%@) does not exist. Resetting local data.", self.zoneID);

        /*
         * If someone delete our zone, lets just start over from the begining
         */
        [self dispatchSync: ^bool{
            NSError* resetError = nil;

            [self _onqueueResetLocalData: &resetError];
            if(resetError) {
                ckksnotice("ckksreset", self, "CloudKit-inspired local reset of %@ ended with error: %@", self.zoneID, resetError);
            } else {
                ckksnotice("ckksreset", self, "CloudKit-inspired local reset of %@ ended successfully", self.zoneID);
            }

            [self _onqueueAdvanceKeyStateMachineToState:SecCKKSZoneKeyStateInitializing withError:nil];
            return true;
        }];

        return false;
    }

    if([error.domain isEqualToString:CKErrorDomain] && (error.code == CKErrorBadContainer)) {
        ckkserror("ckks", self, "Received notice that our container does not exist. Nothing to do.");
        return false;
    }

    return true;
}

#pragma mark CKKSPeerUpdateListener

- (void)selfPeerChanged:(id<CKKSPeerProvider>)provider
{
    // Currently, we have no idea what to do with this. Kick off a key reprocess?
    ckkserror("ckks", self, "Received update that our self identity has changed");
    [self keyStateMachineRequestProcess];
}

- (void)trustedPeerSetChanged:(id<CKKSPeerProvider>)provider
{
    // We might need to share the TLK to some new people, or we might now trust the TLKs we have.
    // The key state machine should handle that, so poke it.
    ckkserror("ckks", self, "Received update that the trust set has changed");

    self.trustedPeersSetChanged = true;
    [self.pokeKeyStateMachineScheduler trigger];
}

#pragma mark - Test Support

- (bool) outgoingQueueEmpty: (NSError * __autoreleasing *) error {
    __block bool ret = false;
    [self dispatchSync: ^bool{
        NSArray* queueEntries = [CKKSOutgoingQueueEntry all: error];
        ret = queueEntries && ([queueEntries count] == 0);
        return true;
    }];

    return ret;
}

- (CKKSResultOperation*)waitForFetchAndIncomingQueueProcessing {
    CKKSResultOperation* op = [self fetchAndProcessCKChanges:CKKSFetchBecauseTesting];
    [op waitUntilFinished];
    return op;
}

- (void)waitForKeyHierarchyReadiness {
    if(self.keyStateReadyDependency) {
        [self.keyStateReadyDependency waitUntilFinished];
    }
}

- (void)cancelPendingOperations {
    @synchronized(self.outgoingQueueOperations) {
        for(NSOperation* op in self.outgoingQueueOperations) {
            [op cancel];
        }
        [self.outgoingQueueOperations removeAllObjects];
    }

    @synchronized(self.incomingQueueOperations) {
        for(NSOperation* op in self.incomingQueueOperations) {
            [op cancel];
        }
        [self.incomingQueueOperations removeAllObjects];
    }

    [super cancelAllOperations];
}

- (void)cancelAllOperations {
    [self.zoneSetupOperation cancel];
    [self.keyStateMachineOperation cancel];
    [self.keyStateReadyDependency cancel];
    [self.keyStateNonTransientDependency cancel];
    [self.zoneChangeFetcher cancel];
    [self.notifyViewChangedScheduler cancel];

    [self cancelPendingOperations];

    [self dispatchSync:^bool{
        [self _onqueueAdvanceKeyStateMachineToState: SecCKKSZoneKeyStateCancelled withError: nil];
        return true;
    }];
}

- (void)halt {
    [super halt];

    // Don't send any more notifications, either
    _notifierClass = nil;
}

- (NSDictionary*)status {
#define stringify(obj) CKKSNilToNSNull([obj description])
#define boolstr(obj) (!!(obj) ? @"yes" : @"no")
    __block NSMutableDictionary* ret = nil;
    __block NSError* error = nil;
    CKKSManifest* manifest = nil;

    ret = [[self fastStatus] mutableCopy];

    manifest = [CKKSManifest latestTrustedManifestForZone:self.zoneName error:&error];
    [self dispatchSync: ^bool {

        CKKSCurrentKeySet* keyset = [CKKSCurrentKeySet loadForZone:self.zoneID];
        if(keyset.error) {
            error = keyset.error;
        }

        NSString* manifestGeneration = manifest ? [NSString stringWithFormat:@"%lu", (unsigned long)manifest.generationCount] : nil;

        if(error) {
            ckkserror("ckks", self, "error during status: %@", error);
        }
        // We actually don't care about this error, especially if it's "no current key pointers"...
        error = nil;

        // Map deviceStates to strings to avoid NSXPC issues. Obj-c, why is this so hard?
        NSArray* deviceStates = [CKKSDeviceStateEntry allInZone:self.zoneID error:&error];
        NSMutableArray<NSString*>* mutDeviceStates = [[NSMutableArray alloc] init];
        [deviceStates enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [mutDeviceStates addObject: [obj description]];
        }];

        NSArray* tlkShares = [CKKSTLKShareRecord allForUUID:keyset.currentTLKPointer.currentKeyUUID zoneID:self.zoneID error:&error];
        NSMutableArray<NSString*>* mutTLKShares = [[NSMutableArray alloc] init];
        [tlkShares enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [mutTLKShares addObject: [obj description]];
        }];

        [ret addEntriesFromDictionary:@{
                 @"statusError":         stringify(error),
                 @"oqe":                 CKKSNilToNSNull([CKKSOutgoingQueueEntry countsByStateInZone:self.zoneID error:&error]),
                 @"iqe":                 CKKSNilToNSNull([CKKSIncomingQueueEntry countsByStateInZone:self.zoneID error:&error]),
                 @"ckmirror":            CKKSNilToNSNull([CKKSMirrorEntry        countsByParentKey:self.zoneID error:&error]),
                 @"devicestates":        CKKSNilToNSNull(mutDeviceStates),
                 @"tlkshares":           CKKSNilToNSNull(mutTLKShares),
                 @"keys":                CKKSNilToNSNull([CKKSKey countsByClass:self.zoneID error:&error]),
                 @"currentTLK":          CKKSNilToNSNull(keyset.tlk.uuid),
                 @"currentClassA":       CKKSNilToNSNull(keyset.classA.uuid),
                 @"currentClassC":       CKKSNilToNSNull(keyset.classC.uuid),
                 @"currentTLKPtr":       CKKSNilToNSNull(keyset.currentTLKPointer.currentKeyUUID),
                 @"currentClassAPtr":    CKKSNilToNSNull(keyset.currentClassAPointer.currentKeyUUID),
                 @"currentClassCPtr":    CKKSNilToNSNull(keyset.currentClassCPointer.currentKeyUUID),
                 @"currentManifestGen":  CKKSNilToNSNull(manifestGeneration),
            }];
        return false;
    }];
    return ret;
}

- (NSDictionary*)fastStatus {

    __block NSDictionary* ret = nil;

    [self dispatchSync: ^bool {

        ret = @{
            @"view":                CKKSNilToNSNull(self.zoneName),
            @"ckaccountstatus":     self.accountStatus == CKAccountStatusCouldNotDetermine ? @"could not determine" :
                self.accountStatus == CKAccountStatusAvailable         ? @"logged in" :
                self.accountStatus == CKAccountStatusRestricted        ? @"restricted" :
                self.accountStatus == CKAccountStatusNoAccount         ? @"logged out" : @"unknown",
            @"accounttracker":      stringify(self.accountTracker),
            @"fetcher":             stringify(self.zoneChangeFetcher),
            @"zoneCreated":         boolstr(self.zoneCreated),
            @"zoneCreatedError":    stringify(self.zoneCreatedError),
            @"zoneSubscribed":      boolstr(self.zoneSubscribed),
            @"zoneSubscribedError": stringify(self.zoneSubscribedError),
            @"keystate":            CKKSNilToNSNull(self.keyHierarchyState),
            @"keyStateError":       stringify(self.keyHierarchyError),
            @"statusError":         [NSNull null],
            @"launchSequence":      CKKSNilToNSNull([self.launch eventsByTime]),

            @"zoneSetupOperation":                 stringify(self.zoneSetupOperation),
            @"keyStateOperation":                  stringify(self.keyStateMachineOperation),
            @"lastIncomingQueueOperation":         stringify(self.lastIncomingQueueOperation),
            @"lastNewTLKOperation":                stringify(self.lastNewTLKOperation),
            @"lastOutgoingQueueOperation":         stringify(self.lastOutgoingQueueOperation),
            @"lastProcessReceivedKeysOperation":   stringify(self.lastProcessReceivedKeysOperation),
            @"lastReencryptOutgoingItemsOperation":stringify(self.lastReencryptOutgoingItemsOperation),
            @"lastScanLocalItemsOperation":        stringify(self.lastScanLocalItemsOperation),
        };
        return false;
    }];

    return ret;
}

#endif /* OCTAGON */
@end
