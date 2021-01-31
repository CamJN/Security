// This file was automatically generated by protocompiler
// DO NOT EDIT!
// Compiled from OTCDPRecoveryInformation.proto

#import <Foundation/Foundation.h>
#import <ProtocolBuffer/PBCodable.h>

#ifdef __cplusplus
#define OTCDPRECOVERYINFORMATION_FUNCTION extern "C"
#else
#define OTCDPRECOVERYINFORMATION_FUNCTION extern
#endif

@interface OTCDPRecoveryInformation : PBCodable <NSCopying>
{
    NSString *_recoveryKey;
    NSString *_recoverySecret;
    BOOL _containsIcdpData;
    BOOL _silentRecoveryAttempt;
    BOOL _useCachedSecret;
    BOOL _usePreviouslyCachedRecoveryKey;
    BOOL _usesMultipleIcsc;
    struct {
        int containsIcdpData:1;
        int silentRecoveryAttempt:1;
        int useCachedSecret:1;
        int usePreviouslyCachedRecoveryKey:1;
        int usesMultipleIcsc:1;
    } _has;
}


@property (nonatomic, readonly) BOOL hasRecoverySecret;
@property (nonatomic, retain) NSString *recoverySecret;

@property (nonatomic) BOOL hasUseCachedSecret;
@property (nonatomic) BOOL useCachedSecret;

@property (nonatomic, readonly) BOOL hasRecoveryKey;
@property (nonatomic, retain) NSString *recoveryKey;

@property (nonatomic) BOOL hasUsePreviouslyCachedRecoveryKey;
@property (nonatomic) BOOL usePreviouslyCachedRecoveryKey;

@property (nonatomic) BOOL hasSilentRecoveryAttempt;
@property (nonatomic) BOOL silentRecoveryAttempt;

@property (nonatomic) BOOL hasContainsIcdpData;
@property (nonatomic) BOOL containsIcdpData;

@property (nonatomic) BOOL hasUsesMultipleIcsc;
@property (nonatomic) BOOL usesMultipleIcsc;

// Performs a shallow copy into other
- (void)copyTo:(OTCDPRecoveryInformation *)other;

// Performs a deep merge from other into self
// If set in other, singular values in self are replaced in self
// Singular composite values are recursively merged
// Repeated values from other are appended to repeated values in self
- (void)mergeFrom:(OTCDPRecoveryInformation *)other;

OTCDPRECOVERYINFORMATION_FUNCTION BOOL OTCDPRecoveryInformationReadFrom(__unsafe_unretained OTCDPRecoveryInformation *self, __unsafe_unretained PBDataReader *reader);

@end
