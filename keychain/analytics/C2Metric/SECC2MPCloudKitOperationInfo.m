// This file was automatically generated by protocompiler
// DO NOT EDIT!
// Compiled from C2Metric.proto

#import "SECC2MPCloudKitOperationInfo.h"
#import <ProtocolBuffer/PBConstants.h>
#import <ProtocolBuffer/PBHashUtil.h>
#import <ProtocolBuffer/PBDataReader.h>

#if !__has_feature(objc_arc)
# error This generated file depends on ARC but it is not enabled; turn on ARC, or use 'objc_use_arc' option to generate non-ARC code.
#endif

@implementation SECC2MPCloudKitOperationInfo

- (BOOL)hasOperationId
{
    return _operationId != nil;
}
@synthesize operationId = _operationId;
- (BOOL)hasOperationType
{
    return _operationType != nil;
}
@synthesize operationType = _operationType;
@synthesize operationTriggered = _operationTriggered;
- (void)setOperationTriggered:(BOOL)v
{
    _has.operationTriggered = YES;
    _operationTriggered = v;
}
- (void)setHasOperationTriggered:(BOOL)f
{
    _has.operationTriggered = f;
}
- (BOOL)hasOperationTriggered
{
    return _has.operationTriggered;
}
@synthesize operationGroupIndex = _operationGroupIndex;
- (void)setOperationGroupIndex:(uint32_t)v
{
    _has.operationGroupIndex = YES;
    _operationGroupIndex = v;
}
- (void)setHasOperationGroupIndex:(BOOL)f
{
    _has.operationGroupIndex = f;
}
- (BOOL)hasOperationGroupIndex
{
    return _has.operationGroupIndex;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ %@", [super description], [self dictionaryRepresentation]];
}

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (self->_operationId)
    {
        [dict setObject:self->_operationId forKey:@"operation_id"];
    }
    if (self->_operationType)
    {
        [dict setObject:self->_operationType forKey:@"operation_type"];
    }
    if (self->_has.operationTriggered)
    {
        [dict setObject:[NSNumber numberWithBool:self->_operationTriggered] forKey:@"operation_triggered"];
    }
    if (self->_has.operationGroupIndex)
    {
        [dict setObject:[NSNumber numberWithUnsignedInt:self->_operationGroupIndex] forKey:@"operation_group_index"];
    }
    return dict;
}

BOOL SECC2MPCloudKitOperationInfoReadFrom(__unsafe_unretained SECC2MPCloudKitOperationInfo *self, __unsafe_unretained PBDataReader *reader) {
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

            case 1 /* operationId */:
            {
                NSString *new_operationId = PBReaderReadString(reader);
                self->_operationId = new_operationId;
            }
            break;
            case 2 /* operationType */:
            {
                NSString *new_operationType = PBReaderReadString(reader);
                self->_operationType = new_operationType;
            }
            break;
            case 101 /* operationTriggered */:
            {
                self->_has.operationTriggered = YES;
                self->_operationTriggered = PBReaderReadBOOL(reader);
            }
            break;
            case 201 /* operationGroupIndex */:
            {
                self->_has.operationGroupIndex = YES;
                self->_operationGroupIndex = PBReaderReadUint32(reader);
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
    return SECC2MPCloudKitOperationInfoReadFrom(self, reader);
}
- (void)writeTo:(PBDataWriter *)writer
{
    /* operationId */
    {
        if (self->_operationId)
        {
            PBDataWriterWriteStringField(writer, self->_operationId, 1);
        }
    }
    /* operationType */
    {
        if (self->_operationType)
        {
            PBDataWriterWriteStringField(writer, self->_operationType, 2);
        }
    }
    /* operationTriggered */
    {
        if (self->_has.operationTriggered)
        {
            PBDataWriterWriteBOOLField(writer, self->_operationTriggered, 101);
        }
    }
    /* operationGroupIndex */
    {
        if (self->_has.operationGroupIndex)
        {
            PBDataWriterWriteUint32Field(writer, self->_operationGroupIndex, 201);
        }
    }
}

- (void)copyTo:(SECC2MPCloudKitOperationInfo *)other
{
    if (_operationId)
    {
        other.operationId = _operationId;
    }
    if (_operationType)
    {
        other.operationType = _operationType;
    }
    if (self->_has.operationTriggered)
    {
        other->_operationTriggered = _operationTriggered;
        other->_has.operationTriggered = YES;
    }
    if (self->_has.operationGroupIndex)
    {
        other->_operationGroupIndex = _operationGroupIndex;
        other->_has.operationGroupIndex = YES;
    }
}

- (id)copyWithZone:(NSZone *)zone
{
    SECC2MPCloudKitOperationInfo *copy = [[[self class] allocWithZone:zone] init];
    copy->_operationId = [_operationId copyWithZone:zone];
    copy->_operationType = [_operationType copyWithZone:zone];
    if (self->_has.operationTriggered)
    {
        copy->_operationTriggered = _operationTriggered;
        copy->_has.operationTriggered = YES;
    }
    if (self->_has.operationGroupIndex)
    {
        copy->_operationGroupIndex = _operationGroupIndex;
        copy->_has.operationGroupIndex = YES;
    }
    return copy;
}

- (BOOL)isEqual:(id)object
{
    SECC2MPCloudKitOperationInfo *other = (SECC2MPCloudKitOperationInfo *)object;
    return [other isMemberOfClass:[self class]]
    &&
    ((!self->_operationId && !other->_operationId) || [self->_operationId isEqual:other->_operationId])
    &&
    ((!self->_operationType && !other->_operationType) || [self->_operationType isEqual:other->_operationType])
    &&
    ((self->_has.operationTriggered && other->_has.operationTriggered && ((self->_operationTriggered && other->_operationTriggered) || (!self->_operationTriggered && !other->_operationTriggered))) || (!self->_has.operationTriggered && !other->_has.operationTriggered))
    &&
    ((self->_has.operationGroupIndex && other->_has.operationGroupIndex && self->_operationGroupIndex == other->_operationGroupIndex) || (!self->_has.operationGroupIndex && !other->_has.operationGroupIndex))
    ;
}

- (NSUInteger)hash
{
    return 0
    ^
    [self->_operationId hash]
    ^
    [self->_operationType hash]
    ^
    (self->_has.operationTriggered ? PBHashInt((NSUInteger)self->_operationTriggered) : 0)
    ^
    (self->_has.operationGroupIndex ? PBHashInt((NSUInteger)self->_operationGroupIndex) : 0)
    ;
}

- (void)mergeFrom:(SECC2MPCloudKitOperationInfo *)other
{
    if (other->_operationId)
    {
        [self setOperationId:other->_operationId];
    }
    if (other->_operationType)
    {
        [self setOperationType:other->_operationType];
    }
    if (other->_has.operationTriggered)
    {
        self->_operationTriggered = other->_operationTriggered;
        self->_has.operationTriggered = YES;
    }
    if (other->_has.operationGroupIndex)
    {
        self->_operationGroupIndex = other->_operationGroupIndex;
        self->_has.operationGroupIndex = YES;
    }
}

@end

