// This file was automatically generated by protocompiler
// DO NOT EDIT!
// Compiled from SecDbBackupRecoverySet.proto

#import "SecDbBackupRecoverySet.h"
#import <ProtocolBuffer/PBConstants.h>
#import <ProtocolBuffer/PBHashUtil.h>
#import <ProtocolBuffer/PBDataReader.h>

#import "SecDbBackupBagIdentity.h"

#if !__has_feature(objc_arc)
# error This generated file depends on ARC but it is not enabled; turn on ARC, or use 'objc_use_arc' option to generate non-ARC code.
#endif

@implementation SecDbBackupRecoverySet

@synthesize recoveryType = _recoveryType;
- (void)setRecoveryType:(int32_t)v
{
    _has.recoveryType = YES;
    _recoveryType = v;
}
- (void)setHasRecoveryType:(BOOL)f
{
    _has.recoveryType = f;
}
- (BOOL)hasRecoveryType
{
    return _has.recoveryType;
}
- (BOOL)hasBagIdentity
{
    return _bagIdentity != nil;
}
@synthesize bagIdentity = _bagIdentity;
- (BOOL)hasWrappedBagSecret
{
    return _wrappedBagSecret != nil;
}
@synthesize wrappedBagSecret = _wrappedBagSecret;
- (BOOL)hasWrappedKCSKSecret
{
    return _wrappedKCSKSecret != nil;
}
@synthesize wrappedKCSKSecret = _wrappedKCSKSecret;
- (BOOL)hasWrappedRecoveryKey
{
    return _wrappedRecoveryKey != nil;
}
@synthesize wrappedRecoveryKey = _wrappedRecoveryKey;

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ %@", [super description], [self dictionaryRepresentation]];
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (self->_has.recoveryType)
    {
        [dict setObject:[NSNumber numberWithInt:self->_recoveryType] forKey:@"recoveryType"];
    }
    if (self->_bagIdentity)
    {
        [dict setObject:[_bagIdentity dictionaryRepresentation] forKey:@"bagIdentity"];
    }
    if (self->_wrappedBagSecret)
    {
        [dict setObject:self->_wrappedBagSecret forKey:@"wrappedBagSecret"];
    }
    if (self->_wrappedKCSKSecret)
    {
        [dict setObject:self->_wrappedKCSKSecret forKey:@"wrappedKCSKSecret"];
    }
    if (self->_wrappedRecoveryKey)
    {
        [dict setObject:self->_wrappedRecoveryKey forKey:@"wrappedRecoveryKey"];
    }
    return dict;
}

BOOL SecDbBackupRecoverySetReadFrom(__unsafe_unretained SecDbBackupRecoverySet *self, __unsafe_unretained PBDataReader *reader) {
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

            case 1 /* recoveryType */:
            {
                self->_has.recoveryType = YES;
                self->_recoveryType = PBReaderReadInt32(reader);
            }
            break;
            case 2 /* bagIdentity */:
            {
                SecDbBackupBagIdentity *new_bagIdentity = [[SecDbBackupBagIdentity alloc] init];
                self->_bagIdentity = new_bagIdentity;
                PBDataReaderMark mark_bagIdentity;
                BOOL markError = !PBReaderPlaceMark(reader, &mark_bagIdentity);
                if (markError)
                {
                    return NO;
                }
                BOOL inError = !SecDbBackupBagIdentityReadFrom(new_bagIdentity, reader);
                if (inError)
                {
                    return NO;
                }
                PBReaderRecallMark(reader, &mark_bagIdentity);
            }
            break;
            case 3 /* wrappedBagSecret */:
            {
                NSData *new_wrappedBagSecret = PBReaderReadData(reader);
                self->_wrappedBagSecret = new_wrappedBagSecret;
            }
            break;
            case 4 /* wrappedKCSKSecret */:
            {
                NSData *new_wrappedKCSKSecret = PBReaderReadData(reader);
                self->_wrappedKCSKSecret = new_wrappedKCSKSecret;
            }
            break;
            case 5 /* wrappedRecoveryKey */:
            {
                NSData *new_wrappedRecoveryKey = PBReaderReadData(reader);
                self->_wrappedRecoveryKey = new_wrappedRecoveryKey;
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
    return SecDbBackupRecoverySetReadFrom(self, reader);
}
- (void)writeTo:(PBDataWriter *)writer
{
    /* recoveryType */
    {
        if (self->_has.recoveryType)
        {
            PBDataWriterWriteInt32Field(writer, self->_recoveryType, 1);
        }
    }
    /* bagIdentity */
    {
        if (self->_bagIdentity != nil)
        {
            PBDataWriterWriteSubmessage(writer, self->_bagIdentity, 2);
        }
    }
    /* wrappedBagSecret */
    {
        if (self->_wrappedBagSecret)
        {
            PBDataWriterWriteDataField(writer, self->_wrappedBagSecret, 3);
        }
    }
    /* wrappedKCSKSecret */
    {
        if (self->_wrappedKCSKSecret)
        {
            PBDataWriterWriteDataField(writer, self->_wrappedKCSKSecret, 4);
        }
    }
    /* wrappedRecoveryKey */
    {
        if (self->_wrappedRecoveryKey)
        {
            PBDataWriterWriteDataField(writer, self->_wrappedRecoveryKey, 5);
        }
    }
}

- (void)copyTo:(SecDbBackupRecoverySet *)other
{
    if (self->_has.recoveryType)
    {
        other->_recoveryType = _recoveryType;
        other->_has.recoveryType = YES;
    }
    if (_bagIdentity)
    {
        other.bagIdentity = _bagIdentity;
    }
    if (_wrappedBagSecret)
    {
        other.wrappedBagSecret = _wrappedBagSecret;
    }
    if (_wrappedKCSKSecret)
    {
        other.wrappedKCSKSecret = _wrappedKCSKSecret;
    }
    if (_wrappedRecoveryKey)
    {
        other.wrappedRecoveryKey = _wrappedRecoveryKey;
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    SecDbBackupRecoverySet *copy = [[[self class] allocWithZone:zone] init];
    if (self->_has.recoveryType)
    {
        copy->_recoveryType = _recoveryType;
        copy->_has.recoveryType = YES;
    }
    copy->_bagIdentity = [_bagIdentity copyWithZone:zone];
    copy->_wrappedBagSecret = [_wrappedBagSecret copyWithZone:zone];
    copy->_wrappedKCSKSecret = [_wrappedKCSKSecret copyWithZone:zone];
    copy->_wrappedRecoveryKey = [_wrappedRecoveryKey copyWithZone:zone];
    return copy;
}

- (BOOL)isEqual:(id)object
{
    SecDbBackupRecoverySet *other = (SecDbBackupRecoverySet *)object;
    return [other isMemberOfClass:[self class]]
    &&
    ((self->_has.recoveryType && other->_has.recoveryType && self->_recoveryType == other->_recoveryType) || (!self->_has.recoveryType && !other->_has.recoveryType))
    &&
    ((!self->_bagIdentity && !other->_bagIdentity) || [self->_bagIdentity isEqual:other->_bagIdentity])
    &&
    ((!self->_wrappedBagSecret && !other->_wrappedBagSecret) || [self->_wrappedBagSecret isEqual:other->_wrappedBagSecret])
    &&
    ((!self->_wrappedKCSKSecret && !other->_wrappedKCSKSecret) || [self->_wrappedKCSKSecret isEqual:other->_wrappedKCSKSecret])
    &&
    ((!self->_wrappedRecoveryKey && !other->_wrappedRecoveryKey) || [self->_wrappedRecoveryKey isEqual:other->_wrappedRecoveryKey])
    ;
}

- (NSUInteger)hash
{
    return 0
    ^
    (self->_has.recoveryType ? PBHashInt((NSUInteger)self->_recoveryType) : 0)
    ^
    [self->_bagIdentity hash]
    ^
    [self->_wrappedBagSecret hash]
    ^
    [self->_wrappedKCSKSecret hash]
    ^
    [self->_wrappedRecoveryKey hash]
    ;
}

- (void)mergeFrom:(SecDbBackupRecoverySet *)other
{
    if (other->_has.recoveryType)
    {
        self->_recoveryType = other->_recoveryType;
        self->_has.recoveryType = YES;
    }
    if (self->_bagIdentity && other->_bagIdentity)
    {
        [self->_bagIdentity mergeFrom:other->_bagIdentity];
    }
    else if (!self->_bagIdentity && other->_bagIdentity)
    {
        [self setBagIdentity:other->_bagIdentity];
    }
    if (other->_wrappedBagSecret)
    {
        [self setWrappedBagSecret:other->_wrappedBagSecret];
    }
    if (other->_wrappedKCSKSecret)
    {
        [self setWrappedKCSKSecret:other->_wrappedKCSKSecret];
    }
    if (other->_wrappedRecoveryKey)
    {
        [self setWrappedRecoveryKey:other->_wrappedRecoveryKey];
    }
}

@end

