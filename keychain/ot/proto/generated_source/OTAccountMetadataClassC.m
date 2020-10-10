// This file was automatically generated by protocompiler
// DO NOT EDIT!
// Compiled from OTAccountMetadataClassC.proto

#import "OTAccountMetadataClassC.h"
#import <ProtocolBuffer/PBConstants.h>
#import <ProtocolBuffer/PBHashUtil.h>
#import <ProtocolBuffer/PBDataReader.h>

#if !__has_feature(objc_arc)
# error This generated file depends on ARC but it is not enabled; turn on ARC, or use 'objc_use_arc' option to generate non-ARC code.
#endif

@implementation OTAccountMetadataClassC

- (BOOL)hasPeerID
{
    return _peerID != nil;
}
@synthesize peerID = _peerID;
@synthesize icloudAccountState = _icloudAccountState;
- (OTAccountMetadataClassC_AccountState)icloudAccountState
{
    return _has.icloudAccountState ? _icloudAccountState : OTAccountMetadataClassC_AccountState_UNKNOWN;
}
- (void)setIcloudAccountState:(OTAccountMetadataClassC_AccountState)v
{
    _has.icloudAccountState = YES;
    _icloudAccountState = v;
}
- (void)setHasIcloudAccountState:(BOOL)f
{
    _has.icloudAccountState = f;
}
- (BOOL)hasIcloudAccountState
{
    return _has.icloudAccountState != 0;
}
- (NSString *)icloudAccountStateAsString:(OTAccountMetadataClassC_AccountState)value
{
    return OTAccountMetadataClassC_AccountStateAsString(value);
}
- (OTAccountMetadataClassC_AccountState)StringAsIcloudAccountState:(NSString *)str
{
    return StringAsOTAccountMetadataClassC_AccountState(str);
}
@synthesize epoch = _epoch;
- (void)setEpoch:(int64_t)v
{
    _has.epoch = YES;
    _epoch = v;
}
- (void)setHasEpoch:(BOOL)f
{
    _has.epoch = f;
}
- (BOOL)hasEpoch
{
    return _has.epoch != 0;
}
- (BOOL)hasAltDSID
{
    return _altDSID != nil;
}
@synthesize altDSID = _altDSID;
@synthesize trustState = _trustState;
- (OTAccountMetadataClassC_TrustState)trustState
{
    return _has.trustState ? _trustState : OTAccountMetadataClassC_TrustState_UNKNOWN;
}
- (void)setTrustState:(OTAccountMetadataClassC_TrustState)v
{
    _has.trustState = YES;
    _trustState = v;
}
- (void)setHasTrustState:(BOOL)f
{
    _has.trustState = f;
}
- (BOOL)hasTrustState
{
    return _has.trustState != 0;
}
- (NSString *)trustStateAsString:(OTAccountMetadataClassC_TrustState)value
{
    return OTAccountMetadataClassC_TrustStateAsString(value);
}
- (OTAccountMetadataClassC_TrustState)StringAsTrustState:(NSString *)str
{
    return StringAsOTAccountMetadataClassC_TrustState(str);
}
@synthesize lastHealthCheckup = _lastHealthCheckup;
- (void)setLastHealthCheckup:(uint64_t)v
{
    _has.lastHealthCheckup = YES;
    _lastHealthCheckup = v;
}
- (void)setHasLastHealthCheckup:(BOOL)f
{
    _has.lastHealthCheckup = f;
}
- (BOOL)hasLastHealthCheckup
{
    return _has.lastHealthCheckup != 0;
}
@synthesize attemptedJoin = _attemptedJoin;
- (OTAccountMetadataClassC_AttemptedAJoinState)attemptedJoin
{
    return _has.attemptedJoin ? _attemptedJoin : OTAccountMetadataClassC_AttemptedAJoinState_UNKNOWN;
}
- (void)setAttemptedJoin:(OTAccountMetadataClassC_AttemptedAJoinState)v
{
    _has.attemptedJoin = YES;
    _attemptedJoin = v;
}
- (void)setHasAttemptedJoin:(BOOL)f
{
    _has.attemptedJoin = f;
}
- (BOOL)hasAttemptedJoin
{
    return _has.attemptedJoin != 0;
}
- (NSString *)attemptedJoinAsString:(OTAccountMetadataClassC_AttemptedAJoinState)value
{
    return OTAccountMetadataClassC_AttemptedAJoinStateAsString(value);
}
- (OTAccountMetadataClassC_AttemptedAJoinState)StringAsAttemptedJoin:(NSString *)str
{
    return StringAsOTAccountMetadataClassC_AttemptedAJoinState(str);
}
@synthesize cdpState = _cdpState;
- (OTAccountMetadataClassC_CDPState)cdpState
{
    return _has.cdpState ? _cdpState : OTAccountMetadataClassC_CDPState_UNKNOWN;
}
- (void)setCdpState:(OTAccountMetadataClassC_CDPState)v
{
    _has.cdpState = YES;
    _cdpState = v;
}
- (void)setHasCdpState:(BOOL)f
{
    _has.cdpState = f;
}
- (BOOL)hasCdpState
{
    return _has.cdpState != 0;
}
- (NSString *)cdpStateAsString:(OTAccountMetadataClassC_CDPState)value
{
    return OTAccountMetadataClassC_CDPStateAsString(value);
}
- (OTAccountMetadataClassC_CDPState)StringAsCdpState:(NSString *)str
{
    return StringAsOTAccountMetadataClassC_CDPState(str);
}
- (BOOL)hasSyncingPolicy
{
    return _syncingPolicy != nil;
}
@synthesize syncingPolicy = _syncingPolicy;
@synthesize syncingViews = _syncingViews;
- (void)clearSyncingViews
{
    [_syncingViews removeAllObjects];
}
- (void)addSyncingView:(NSString *)i
{
    if (!_syncingViews)
    {
        _syncingViews = [[NSMutableArray alloc] init];
    }
    [_syncingViews addObject:i];
}
- (NSUInteger)syncingViewsCount
{
    return [_syncingViews count];
}
- (NSString *)syncingViewAtIndex:(NSUInteger)idx
{
    return [_syncingViews objectAtIndex:idx];
}
+ (Class)syncingViewType
{
    return [NSString class];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ %@", [super description], [self dictionaryRepresentation]];
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (self->_peerID)
    {
        [dict setObject:self->_peerID forKey:@"peerID"];
    }
    if (self->_has.icloudAccountState)
    {
        [dict setObject:OTAccountMetadataClassC_AccountStateAsString(self->_icloudAccountState) forKey:@"icloudAccountState"];
    }
    if (self->_has.epoch)
    {
        [dict setObject:[NSNumber numberWithLongLong:self->_epoch] forKey:@"epoch"];
    }
    if (self->_altDSID)
    {
        [dict setObject:self->_altDSID forKey:@"altDSID"];
    }
    if (self->_has.trustState)
    {
        [dict setObject:OTAccountMetadataClassC_TrustStateAsString(self->_trustState) forKey:@"trustState"];
    }
    if (self->_has.lastHealthCheckup)
    {
        [dict setObject:[NSNumber numberWithUnsignedLongLong:self->_lastHealthCheckup] forKey:@"lastHealthCheckup"];
    }
    if (self->_has.attemptedJoin)
    {
        [dict setObject:OTAccountMetadataClassC_AttemptedAJoinStateAsString(self->_attemptedJoin) forKey:@"attemptedJoin"];
    }
    if (self->_has.cdpState)
    {
        [dict setObject:OTAccountMetadataClassC_CDPStateAsString(self->_cdpState) forKey:@"cdpState"];
    }
    if (self->_syncingPolicy)
    {
        [dict setObject:self->_syncingPolicy forKey:@"syncingPolicy"];
    }
    if (self->_syncingViews)
    {
        [dict setObject:self->_syncingViews forKey:@"syncingView"];
    }
    return dict;
}

BOOL OTAccountMetadataClassCReadFrom(__unsafe_unretained OTAccountMetadataClassC *self, __unsafe_unretained PBDataReader *reader) {
    while (PBReaderHasMoreData(reader)) {
        uint32_t tag = 0;
        uint8_t aType = 0;

        PBReaderReadTag32AndType(reader, &tag, &aType);

        if (PBReaderHasError(reader))
            break;

        if (aType == TYPE_END_GROUP) {
            break;
        }

        switch (tag) {

            case 1 /* peerID */:
            {
                NSString *new_peerID = PBReaderReadString(reader);
                self->_peerID = new_peerID;
            }
            break;
            case 2 /* icloudAccountState */:
            {
                self->_has.icloudAccountState = YES;
                self->_icloudAccountState = PBReaderReadInt32(reader);
            }
            break;
            case 3 /* epoch */:
            {
                self->_has.epoch = YES;
                self->_epoch = PBReaderReadInt64(reader);
            }
            break;
            case 4 /* altDSID */:
            {
                NSString *new_altDSID = PBReaderReadString(reader);
                self->_altDSID = new_altDSID;
            }
            break;
            case 5 /* trustState */:
            {
                self->_has.trustState = YES;
                self->_trustState = PBReaderReadInt32(reader);
            }
            break;
            case 6 /* lastHealthCheckup */:
            {
                self->_has.lastHealthCheckup = YES;
                self->_lastHealthCheckup = PBReaderReadUint64(reader);
            }
            break;
            case 7 /* attemptedJoin */:
            {
                self->_has.attemptedJoin = YES;
                self->_attemptedJoin = PBReaderReadInt32(reader);
            }
            break;
            case 8 /* cdpState */:
            {
                self->_has.cdpState = YES;
                self->_cdpState = PBReaderReadInt32(reader);
            }
            break;
            case 9 /* syncingPolicy */:
            {
                NSData *new_syncingPolicy = PBReaderReadData(reader);
                self->_syncingPolicy = new_syncingPolicy;
            }
            break;
            case 10 /* syncingViews */:
            {
                NSString *new_syncingViews = PBReaderReadString(reader);
                if (new_syncingViews)
                {
                    [self addSyncingView:new_syncingViews];
                }
            }
            break;
            default:
                if (!PBReaderSkipValueWithTag(reader, tag, aType))
                    return NO;
                break;
        }
    }
    return !PBReaderHasError(reader);
}

- (BOOL)readFrom:(PBDataReader *)reader
{
    return OTAccountMetadataClassCReadFrom(self, reader);
}
- (void)writeTo:(PBDataWriter *)writer
{
    /* peerID */
    {
        if (self->_peerID)
        {
            PBDataWriterWriteStringField(writer, self->_peerID, 1);
        }
    }
    /* icloudAccountState */
    {
        if (self->_has.icloudAccountState)
        {
            PBDataWriterWriteInt32Field(writer, self->_icloudAccountState, 2);
        }
    }
    /* epoch */
    {
        if (self->_has.epoch)
        {
            PBDataWriterWriteInt64Field(writer, self->_epoch, 3);
        }
    }
    /* altDSID */
    {
        if (self->_altDSID)
        {
            PBDataWriterWriteStringField(writer, self->_altDSID, 4);
        }
    }
    /* trustState */
    {
        if (self->_has.trustState)
        {
            PBDataWriterWriteInt32Field(writer, self->_trustState, 5);
        }
    }
    /* lastHealthCheckup */
    {
        if (self->_has.lastHealthCheckup)
        {
            PBDataWriterWriteUint64Field(writer, self->_lastHealthCheckup, 6);
        }
    }
    /* attemptedJoin */
    {
        if (self->_has.attemptedJoin)
        {
            PBDataWriterWriteInt32Field(writer, self->_attemptedJoin, 7);
        }
    }
    /* cdpState */
    {
        if (self->_has.cdpState)
        {
            PBDataWriterWriteInt32Field(writer, self->_cdpState, 8);
        }
    }
    /* syncingPolicy */
    {
        if (self->_syncingPolicy)
        {
            PBDataWriterWriteDataField(writer, self->_syncingPolicy, 9);
        }
    }
    /* syncingViews */
    {
        for (NSString *s_syncingViews in self->_syncingViews)
        {
            PBDataWriterWriteStringField(writer, s_syncingViews, 10);
        }
    }
}

- (void)copyTo:(OTAccountMetadataClassC *)other
{
    if (_peerID)
    {
        other.peerID = _peerID;
    }
    if (self->_has.icloudAccountState)
    {
        other->_icloudAccountState = _icloudAccountState;
        other->_has.icloudAccountState = YES;
    }
    if (self->_has.epoch)
    {
        other->_epoch = _epoch;
        other->_has.epoch = YES;
    }
    if (_altDSID)
    {
        other.altDSID = _altDSID;
    }
    if (self->_has.trustState)
    {
        other->_trustState = _trustState;
        other->_has.trustState = YES;
    }
    if (self->_has.lastHealthCheckup)
    {
        other->_lastHealthCheckup = _lastHealthCheckup;
        other->_has.lastHealthCheckup = YES;
    }
    if (self->_has.attemptedJoin)
    {
        other->_attemptedJoin = _attemptedJoin;
        other->_has.attemptedJoin = YES;
    }
    if (self->_has.cdpState)
    {
        other->_cdpState = _cdpState;
        other->_has.cdpState = YES;
    }
    if (_syncingPolicy)
    {
        other.syncingPolicy = _syncingPolicy;
    }
    if ([self syncingViewsCount])
    {
        [other clearSyncingViews];
        NSUInteger syncingViewsCnt = [self syncingViewsCount];
        for (NSUInteger i = 0; i < syncingViewsCnt; i++)
        {
            [other addSyncingView:[self syncingViewAtIndex:i]];
        }
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    OTAccountMetadataClassC *copy = [[[self class] allocWithZone:zone] init];
    copy->_peerID = [_peerID copyWithZone:zone];
    if (self->_has.icloudAccountState)
    {
        copy->_icloudAccountState = _icloudAccountState;
        copy->_has.icloudAccountState = YES;
    }
    if (self->_has.epoch)
    {
        copy->_epoch = _epoch;
        copy->_has.epoch = YES;
    }
    copy->_altDSID = [_altDSID copyWithZone:zone];
    if (self->_has.trustState)
    {
        copy->_trustState = _trustState;
        copy->_has.trustState = YES;
    }
    if (self->_has.lastHealthCheckup)
    {
        copy->_lastHealthCheckup = _lastHealthCheckup;
        copy->_has.lastHealthCheckup = YES;
    }
    if (self->_has.attemptedJoin)
    {
        copy->_attemptedJoin = _attemptedJoin;
        copy->_has.attemptedJoin = YES;
    }
    if (self->_has.cdpState)
    {
        copy->_cdpState = _cdpState;
        copy->_has.cdpState = YES;
    }
    copy->_syncingPolicy = [_syncingPolicy copyWithZone:zone];
    for (NSString *v in _syncingViews)
    {
        NSString *vCopy = [v copyWithZone:zone];
        [copy addSyncingView:vCopy];
    }
    return copy;
}

- (BOOL)isEqual:(id)object
{
    OTAccountMetadataClassC *other = (OTAccountMetadataClassC *)object;
    return [other isMemberOfClass:[self class]]
    &&
    ((!self->_peerID && !other->_peerID) || [self->_peerID isEqual:other->_peerID])
    &&
    ((self->_has.icloudAccountState && other->_has.icloudAccountState && self->_icloudAccountState == other->_icloudAccountState) || (!self->_has.icloudAccountState && !other->_has.icloudAccountState))
    &&
    ((self->_has.epoch && other->_has.epoch && self->_epoch == other->_epoch) || (!self->_has.epoch && !other->_has.epoch))
    &&
    ((!self->_altDSID && !other->_altDSID) || [self->_altDSID isEqual:other->_altDSID])
    &&
    ((self->_has.trustState && other->_has.trustState && self->_trustState == other->_trustState) || (!self->_has.trustState && !other->_has.trustState))
    &&
    ((self->_has.lastHealthCheckup && other->_has.lastHealthCheckup && self->_lastHealthCheckup == other->_lastHealthCheckup) || (!self->_has.lastHealthCheckup && !other->_has.lastHealthCheckup))
    &&
    ((self->_has.attemptedJoin && other->_has.attemptedJoin && self->_attemptedJoin == other->_attemptedJoin) || (!self->_has.attemptedJoin && !other->_has.attemptedJoin))
    &&
    ((self->_has.cdpState && other->_has.cdpState && self->_cdpState == other->_cdpState) || (!self->_has.cdpState && !other->_has.cdpState))
    &&
    ((!self->_syncingPolicy && !other->_syncingPolicy) || [self->_syncingPolicy isEqual:other->_syncingPolicy])
    &&
    ((!self->_syncingViews && !other->_syncingViews) || [self->_syncingViews isEqual:other->_syncingViews])
    ;
}

- (NSUInteger)hash
{
    return 0
    ^
    [self->_peerID hash]
    ^
    (self->_has.icloudAccountState ? PBHashInt((NSUInteger)self->_icloudAccountState) : 0)
    ^
    (self->_has.epoch ? PBHashInt((NSUInteger)self->_epoch) : 0)
    ^
    [self->_altDSID hash]
    ^
    (self->_has.trustState ? PBHashInt((NSUInteger)self->_trustState) : 0)
    ^
    (self->_has.lastHealthCheckup ? PBHashInt((NSUInteger)self->_lastHealthCheckup) : 0)
    ^
    (self->_has.attemptedJoin ? PBHashInt((NSUInteger)self->_attemptedJoin) : 0)
    ^
    (self->_has.cdpState ? PBHashInt((NSUInteger)self->_cdpState) : 0)
    ^
    [self->_syncingPolicy hash]
    ^
    [self->_syncingViews hash]
    ;
}

- (void)mergeFrom:(OTAccountMetadataClassC *)other
{
    if (other->_peerID)
    {
        [self setPeerID:other->_peerID];
    }
    if (other->_has.icloudAccountState)
    {
        self->_icloudAccountState = other->_icloudAccountState;
        self->_has.icloudAccountState = YES;
    }
    if (other->_has.epoch)
    {
        self->_epoch = other->_epoch;
        self->_has.epoch = YES;
    }
    if (other->_altDSID)
    {
        [self setAltDSID:other->_altDSID];
    }
    if (other->_has.trustState)
    {
        self->_trustState = other->_trustState;
        self->_has.trustState = YES;
    }
    if (other->_has.lastHealthCheckup)
    {
        self->_lastHealthCheckup = other->_lastHealthCheckup;
        self->_has.lastHealthCheckup = YES;
    }
    if (other->_has.attemptedJoin)
    {
        self->_attemptedJoin = other->_attemptedJoin;
        self->_has.attemptedJoin = YES;
    }
    if (other->_has.cdpState)
    {
        self->_cdpState = other->_cdpState;
        self->_has.cdpState = YES;
    }
    if (other->_syncingPolicy)
    {
        [self setSyncingPolicy:other->_syncingPolicy];
    }
    for (NSString *iter_syncingViews in other->_syncingViews)
    {
        [self addSyncingView:iter_syncingViews];
    }
}

@end
