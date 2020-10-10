/*
 * Copyright (c) 2007,2009-2010,2012 Apple Inc. All Rights Reserved.
 */

#include <CoreFoundation/CoreFoundation.h>
#include <Security/SecCertificate.h>
#include <Security/SecCertificatePriv.h>
#include <Security/SecPolicyPriv.h>
#include <Security/SecTrust.h>
#include <Security/SecTrustPriv.h>
#include <Security/SecKey.h>
#include <CommonCrypto/CommonDigest.h>

#include <stdlib.h>
#include <unistd.h>

#include <utilities/SecIOFormat.h>
#include <utilities/SecCFWrappers.h>

#include "shared_regressions.h"

/* subject:/CN=iPhone Developer: Katherine Kojima/OU=Core OS Plus Others/O=Core OS Plus Others/C=usa */
/* issuer :/C=US/O=Apple Inc./OU=Apple Worldwide Developer Relations/CN=Apple Worldwide Developer Relations Certification Authority */
unsigned char codesigning_certificate[1415]={
0x30,0x82,0x05,0x83,0x30,0x82,0x04,0x6B,0xA0,0x03,0x02,0x01,0x02,0x02,0x08,0x70,
0xA9,0x16,0x20,0x02,0xA2,0xD4,0x50,0x30,0x0D,0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,
0x0D,0x01,0x01,0x05,0x05,0x00,0x30,0x81,0x96,0x31,0x0B,0x30,0x09,0x06,0x03,0x55,
0x04,0x06,0x13,0x02,0x55,0x53,0x31,0x13,0x30,0x11,0x06,0x03,0x55,0x04,0x0A,0x0C,
0x0A,0x41,0x70,0x70,0x6C,0x65,0x20,0x49,0x6E,0x63,0x2E,0x31,0x2C,0x30,0x2A,0x06,
0x03,0x55,0x04,0x0B,0x0C,0x23,0x41,0x70,0x70,0x6C,0x65,0x20,0x57,0x6F,0x72,0x6C,
0x64,0x77,0x69,0x64,0x65,0x20,0x44,0x65,0x76,0x65,0x6C,0x6F,0x70,0x65,0x72,0x20,
0x52,0x65,0x6C,0x61,0x74,0x69,0x6F,0x6E,0x73,0x31,0x44,0x30,0x42,0x06,0x03,0x55,
0x04,0x03,0x0C,0x3B,0x41,0x70,0x70,0x6C,0x65,0x20,0x57,0x6F,0x72,0x6C,0x64,0x77,
0x69,0x64,0x65,0x20,0x44,0x65,0x76,0x65,0x6C,0x6F,0x70,0x65,0x72,0x20,0x52,0x65,
0x6C,0x61,0x74,0x69,0x6F,0x6E,0x73,0x20,0x43,0x65,0x72,0x74,0x69,0x66,0x69,0x63,
0x61,0x74,0x69,0x6F,0x6E,0x20,0x41,0x75,0x74,0x68,0x6F,0x72,0x69,0x74,0x79,0x30,
0x1E,0x17,0x0D,0x30,0x38,0x30,0x33,0x32,0x36,0x31,0x37,0x30,0x37,0x34,0x36,0x5A,
0x17,0x0D,0x30,0x38,0x30,0x39,0x32,0x34,0x31,0x37,0x30,0x37,0x34,0x36,0x5A,0x30,
0x77,0x31,0x2B,0x30,0x29,0x06,0x03,0x55,0x04,0x03,0x0C,0x22,0x69,0x50,0x68,0x6F,
0x6E,0x65,0x20,0x44,0x65,0x76,0x65,0x6C,0x6F,0x70,0x65,0x72,0x3A,0x20,0x4B,0x61,
0x74,0x68,0x65,0x72,0x69,0x6E,0x65,0x20,0x4B,0x6F,0x6A,0x69,0x6D,0x61,0x31,0x1C,
0x30,0x1A,0x06,0x03,0x55,0x04,0x0B,0x0C,0x13,0x43,0x6F,0x72,0x65,0x20,0x4F,0x53,
0x20,0x50,0x6C,0x75,0x73,0x20,0x4F,0x74,0x68,0x65,0x72,0x73,0x31,0x1C,0x30,0x1A,
0x06,0x03,0x55,0x04,0x0A,0x0C,0x13,0x43,0x6F,0x72,0x65,0x20,0x4F,0x53,0x20,0x50,
0x6C,0x75,0x73,0x20,0x4F,0x74,0x68,0x65,0x72,0x73,0x31,0x0C,0x30,0x0A,0x06,0x03,
0x55,0x04,0x06,0x13,0x03,0x75,0x73,0x61,0x30,0x82,0x01,0x22,0x30,0x0D,0x06,0x09,
0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,0x01,0x05,0x00,0x03,0x82,0x01,0x0F,0x00,
0x30,0x82,0x01,0x0A,0x02,0x82,0x01,0x01,0x00,0xD4,0x2B,0xF2,0x10,0x71,0x0B,0xBB,
0x3D,0xA0,0x1A,0x32,0x41,0xBC,0xA9,0x55,0xF4,0xFB,0x6C,0x9C,0xB5,0x32,0x52,0x10,
0x7E,0x41,0xF4,0x2C,0x18,0x3A,0x4F,0x32,0x9D,0xA3,0x64,0x28,0xDD,0x94,0xD0,0xB8,
0x3F,0xF9,0x7C,0x62,0xE6,0xF5,0xF1,0x16,0x0D,0x7F,0xBA,0xEC,0xBF,0xD9,0x95,0xD4,
0x7A,0xD7,0x4D,0x32,0x0F,0xCD,0x6D,0xBC,0xF3,0x10,0xDE,0xE8,0x5D,0xA1,0xDA,0x98,
0x8F,0x6C,0x75,0xF7,0x7B,0xBE,0x33,0x43,0xBD,0x95,0xFA,0x35,0xD6,0x77,0x81,0x68,
0x02,0x9C,0x41,0x99,0x0B,0x53,0x5F,0x58,0xF3,0x85,0x4C,0xAB,0x06,0xC2,0xC0,0xC4,
0xD8,0x68,0x64,0xE3,0x14,0x5F,0x62,0x75,0xD5,0x66,0x9B,0xEE,0x4A,0x49,0xBA,0xC7,
0x7B,0xD1,0xE6,0x96,0x9D,0xE5,0xEF,0x99,0x0E,0x87,0xEC,0xE3,0xA4,0x54,0x3E,0x19,
0xBB,0x87,0x53,0x9C,0x3C,0x6A,0x94,0x6B,0x22,0x1A,0x01,0xAF,0x21,0xD5,0xDA,0xB0,
0x92,0xE0,0x70,0x61,0xDD,0xC1,0x37,0x60,0x1F,0xC3,0xB0,0xFC,0xB3,0x00,0x4A,0x56,
0x9D,0x70,0xC3,0xDE,0x66,0xD0,0xEF,0x39,0x88,0x48,0xBD,0x6D,0xA6,0xB2,0x2C,0x0A,
0x78,0xCE,0x05,0x62,0x9B,0xE9,0x18,0x4E,0x59,0xC8,0xDC,0xD3,0xDF,0xB6,0x77,0xB5,
0xA3,0xDA,0x62,0x15,0x9A,0x50,0x1E,0x28,0x55,0x70,0xC2,0xB7,0x97,0x63,0x00,0x1E,
0x0E,0x3A,0x8B,0xA6,0x13,0xE5,0xE0,0xD6,0xE6,0xFA,0x61,0xDE,0x5F,0x30,0x72,0xAA,
0xE4,0xBA,0x21,0x74,0x63,0x4A,0xF2,0x18,0x4C,0x99,0x8D,0x75,0x27,0x91,0xF9,0xD4,
0x08,0xAE,0xB6,0xDA,0x69,0x33,0x06,0x7F,0x17,0x02,0x03,0x01,0x00,0x01,0xA3,0x82,
0x01,0xF1,0x30,0x82,0x01,0xED,0x30,0x0C,0x06,0x03,0x55,0x1D,0x13,0x01,0x01,0xFF,
0x04,0x02,0x30,0x00,0x30,0x0E,0x06,0x03,0x55,0x1D,0x0F,0x01,0x01,0xFF,0x04,0x04,
0x03,0x02,0x07,0x80,0x30,0x16,0x06,0x03,0x55,0x1D,0x25,0x01,0x01,0xFF,0x04,0x0C,
0x30,0x0A,0x06,0x08,0x2B,0x06,0x01,0x05,0x05,0x07,0x03,0x03,0x30,0x1D,0x06,0x03,
0x55,0x1D,0x0E,0x04,0x16,0x04,0x14,0x6A,0x6D,0x56,0xC6,0xA5,0x0E,0xC2,0x97,0xF7,
0x17,0x48,0xBE,0xA0,0x07,0xFF,0x77,0xE9,0xEF,0xB2,0xED,0x30,0x1F,0x06,0x03,0x55,
0x1D,0x23,0x04,0x18,0x30,0x16,0x80,0x14,0x88,0x27,0x17,0x09,0xA9,0xB6,0x18,0x60,
0x8B,0xEC,0xEB,0xBA,0xF6,0x47,0x59,0xC5,0x52,0x54,0xA3,0xB7,0x30,0x82,0x01,0x0F,
0x06,0x03,0x55,0x1D,0x20,0x04,0x82,0x01,0x06,0x30,0x82,0x01,0x02,0x30,0x81,0xFF,
0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x63,0x64,0x05,0x01,0x30,0x81,0xF1,0x30,0x81,
0xC3,0x06,0x08,0x2B,0x06,0x01,0x05,0x05,0x07,0x02,0x02,0x30,0x81,0xB6,0x0C,0x81,
0xB3,0x52,0x65,0x6C,0x69,0x61,0x6E,0x63,0x65,0x20,0x6F,0x6E,0x20,0x74,0x68,0x69,
0x73,0x20,0x63,0x65,0x72,0x74,0x69,0x66,0x69,0x63,0x61,0x74,0x65,0x20,0x62,0x79,
0x20,0x61,0x6E,0x79,0x20,0x70,0x61,0x72,0x74,0x79,0x20,0x61,0x73,0x73,0x75,0x6D,
0x65,0x73,0x20,0x61,0x63,0x63,0x65,0x70,0x74,0x61,0x6E,0x63,0x65,0x20,0x6F,0x66,
0x20,0x74,0x68,0x65,0x20,0x74,0x68,0x65,0x6E,0x20,0x61,0x70,0x70,0x6C,0x69,0x63,
0x61,0x62,0x6C,0x65,0x20,0x73,0x74,0x61,0x6E,0x64,0x61,0x72,0x64,0x20,0x74,0x65,
0x72,0x6D,0x73,0x20,0x61,0x6E,0x64,0x20,0x63,0x6F,0x6E,0x64,0x69,0x74,0x69,0x6F,
0x6E,0x73,0x20,0x6F,0x66,0x20,0x75,0x73,0x65,0x2C,0x20,0x63,0x65,0x72,0x74,0x69,
0x66,0x69,0x63,0x61,0x74,0x65,0x20,0x70,0x6F,0x6C,0x69,0x63,0x79,0x20,0x61,0x6E,
0x64,0x20,0x63,0x65,0x72,0x74,0x69,0x66,0x69,0x63,0x61,0x74,0x69,0x6F,0x6E,0x20,
0x70,0x72,0x61,0x63,0x74,0x69,0x63,0x65,0x20,0x73,0x74,0x61,0x74,0x65,0x6D,0x65,
0x6E,0x74,0x73,0x2E,0x30,0x29,0x06,0x08,0x2B,0x06,0x01,0x05,0x05,0x07,0x02,0x01,
0x16,0x1D,0x68,0x74,0x74,0x70,0x3A,0x2F,0x2F,0x77,0x77,0x77,0x2E,0x61,0x70,0x70,
0x6C,0x65,0x2E,0x63,0x6F,0x6D,0x2F,0x61,0x70,0x70,0x6C,0x65,0x63,0x61,0x2F,0x30,
0x4D,0x06,0x03,0x55,0x1D,0x1F,0x04,0x46,0x30,0x44,0x30,0x42,0xA0,0x40,0xA0,0x3E,
0x86,0x3C,0x68,0x74,0x74,0x70,0x3A,0x2F,0x2F,0x64,0x65,0x76,0x65,0x6C,0x6F,0x70,
0x65,0x72,0x2E,0x61,0x70,0x70,0x6C,0x65,0x2E,0x63,0x6F,0x6D,0x2F,0x63,0x65,0x72,
0x74,0x69,0x66,0x69,0x63,0x61,0x74,0x69,0x6F,0x6E,0x61,0x75,0x74,0x68,0x6F,0x72,
0x69,0x74,0x79,0x2F,0x77,0x77,0x64,0x72,0x63,0x61,0x2E,0x63,0x72,0x6C,0x30,0x13,
0x06,0x0A,0x2A,0x86,0x48,0x86,0xF7,0x63,0x64,0x06,0x01,0x02,0x01,0x01,0xFF,0x04,
0x02,0x05,0x00,0x30,0x0D,0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,0x05,
0x05,0x00,0x03,0x82,0x01,0x01,0x00,0xA1,0x1D,0x8C,0xB9,0x21,0x59,0xC8,0xC0,0x08,
0x25,0x97,0x78,0x0D,0x04,0x14,0x85,0xA8,0xFC,0xC3,0xB1,0x7E,0x72,0x45,0x4C,0x96,
0x82,0x90,0x73,0x68,0x24,0x65,0x11,0x0F,0xB8,0x0D,0xB8,0xE4,0x46,0xD5,0x61,0x01,
0x64,0xB8,0x51,0xF8,0xAE,0xE7,0xCF,0xF2,0x7A,0x93,0x78,0xC7,0x9A,0xD3,0xF4,0xF8,
0x04,0xDB,0xF1,0x4A,0xDB,0x05,0x98,0x2F,0xF3,0x39,0x37,0xB0,0x2B,0x49,0x9A,0x82,
0x36,0x63,0xF4,0xB3,0x70,0x75,0x43,0xE3,0xF1,0xBD,0xB5,0x68,0x0C,0xB3,0x7E,0xA3,
0xB3,0x29,0x55,0xD2,0x34,0xD8,0x13,0xB5,0x87,0xD3,0xCE,0xEB,0x26,0xE5,0xCB,0x1F,
0xF1,0xE1,0x89,0x7A,0xB0,0x39,0xB2,0x2E,0x88,0x76,0xE9,0x68,0x69,0x4E,0x90,0xB4,
0x7C,0x42,0x7A,0x2C,0xDF,0x33,0xCF,0x2F,0xBD,0x38,0x3A,0xCC,0xB3,0xC7,0x47,0x9C,
0xC4,0x87,0xCE,0x1A,0x1E,0xF4,0xBB,0xC9,0x97,0x35,0x1C,0x65,0xC2,0xF0,0x2F,0x98,
0x50,0x96,0xA6,0x6C,0xF5,0x1B,0x45,0xE6,0x48,0xBE,0x17,0xFB,0xF6,0x61,0x3E,0x94,
0xF3,0x49,0x57,0xB5,0x54,0x5F,0xE1,0x92,0x30,0xF9,0xC6,0xB7,0x21,0xE0,0x30,0x64,
0x83,0xE7,0x49,0x97,0x8D,0xDC,0xE5,0x9D,0x89,0xA9,0x14,0x2E,0xEF,0x21,0x00,0xBA,
0x13,0x63,0xF4,0xCD,0x2F,0x61,0x17,0x58,0xAB,0xD3,0xA8,0x06,0x54,0x5F,0x60,0xB3,
0xBE,0xED,0xE8,0xF8,0xA4,0x29,0x2F,0xE1,0x4A,0x0E,0xB1,0xFE,0xCE,0x73,0x14,0x9A,
0x3A,0x95,0xFC,0xC8,0xB6,0x53,0xBC,0xBF,0x3A,0xB0,0xAE,0x80,0x76,0xF5,0x57,0x47,
0xD2,0x1C,0x08,0x19,0x22,0xF2,0x6D,
};

/* subject:/C=US/O=Apple Inc./OU=Apple Worldwide Developer Relations/CN=Apple Worldwide Developer Relations Certification Authority */
/* issuer :/C=US/O=Apple Inc./OU=Apple Certification Authority/CN=Apple Root CA */
unsigned char wwdr_intermediate_cert[1063]={
0x30,0x82,0x04,0x23,0x30,0x82,0x03,0x0B,0xA0,0x03,0x02,0x01,0x02,0x02,0x01,0x19,
0x30,0x0D,0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,0x05,0x05,0x00,0x30,
0x62,0x31,0x0B,0x30,0x09,0x06,0x03,0x55,0x04,0x06,0x13,0x02,0x55,0x53,0x31,0x13,
0x30,0x11,0x06,0x03,0x55,0x04,0x0A,0x13,0x0A,0x41,0x70,0x70,0x6C,0x65,0x20,0x49,
0x6E,0x63,0x2E,0x31,0x26,0x30,0x24,0x06,0x03,0x55,0x04,0x0B,0x13,0x1D,0x41,0x70,
0x70,0x6C,0x65,0x20,0x43,0x65,0x72,0x74,0x69,0x66,0x69,0x63,0x61,0x74,0x69,0x6F,
0x6E,0x20,0x41,0x75,0x74,0x68,0x6F,0x72,0x69,0x74,0x79,0x31,0x16,0x30,0x14,0x06,
0x03,0x55,0x04,0x03,0x13,0x0D,0x41,0x70,0x70,0x6C,0x65,0x20,0x52,0x6F,0x6F,0x74,
0x20,0x43,0x41,0x30,0x1E,0x17,0x0D,0x30,0x38,0x30,0x32,0x31,0x34,0x31,0x38,0x35,
0x36,0x33,0x35,0x5A,0x17,0x0D,0x31,0x36,0x30,0x32,0x31,0x34,0x31,0x38,0x35,0x36,
0x33,0x35,0x5A,0x30,0x81,0x96,0x31,0x0B,0x30,0x09,0x06,0x03,0x55,0x04,0x06,0x13,
0x02,0x55,0x53,0x31,0x13,0x30,0x11,0x06,0x03,0x55,0x04,0x0A,0x0C,0x0A,0x41,0x70,
0x70,0x6C,0x65,0x20,0x49,0x6E,0x63,0x2E,0x31,0x2C,0x30,0x2A,0x06,0x03,0x55,0x04,
0x0B,0x0C,0x23,0x41,0x70,0x70,0x6C,0x65,0x20,0x57,0x6F,0x72,0x6C,0x64,0x77,0x69,
0x64,0x65,0x20,0x44,0x65,0x76,0x65,0x6C,0x6F,0x70,0x65,0x72,0x20,0x52,0x65,0x6C,
0x61,0x74,0x69,0x6F,0x6E,0x73,0x31,0x44,0x30,0x42,0x06,0x03,0x55,0x04,0x03,0x0C,
0x3B,0x41,0x70,0x70,0x6C,0x65,0x20,0x57,0x6F,0x72,0x6C,0x64,0x77,0x69,0x64,0x65,
0x20,0x44,0x65,0x76,0x65,0x6C,0x6F,0x70,0x65,0x72,0x20,0x52,0x65,0x6C,0x61,0x74,
0x69,0x6F,0x6E,0x73,0x20,0x43,0x65,0x72,0x74,0x69,0x66,0x69,0x63,0x61,0x74,0x69,
0x6F,0x6E,0x20,0x41,0x75,0x74,0x68,0x6F,0x72,0x69,0x74,0x79,0x30,0x82,0x01,0x22,
0x30,0x0D,0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,0x01,0x05,0x00,0x03,
0x82,0x01,0x0F,0x00,0x30,0x82,0x01,0x0A,0x02,0x82,0x01,0x01,0x00,0xCA,0x38,0x54,
0xA6,0xCB,0x56,0xAA,0xC8,0x24,0x39,0x48,0xE9,0x8C,0xEE,0xEC,0x5F,0xB8,0x7F,0x26,
0x91,0xBC,0x34,0x53,0x7A,0xCE,0x7C,0x63,0x80,0x61,0x77,0x64,0x5E,0xA5,0x07,0x23,
0xB6,0x39,0xFE,0x50,0x2D,0x15,0x56,0x58,0x70,0x2D,0x7E,0xC4,0x6E,0xC1,0x4A,0x85,
0x3E,0x2F,0xF0,0xDE,0x84,0x1A,0xA1,0x57,0xC9,0xAF,0x7B,0x18,0xFF,0x6A,0xFA,0x15,
0x12,0x49,0x15,0x08,0x19,0xAC,0xAA,0xDB,0x2A,0x32,0xED,0x96,0x63,0x68,0x52,0x15,
0x3D,0x8C,0x8A,0xEC,0xBF,0x6B,0x18,0x95,0xE0,0x03,0xAC,0x01,0x7D,0x97,0x05,0x67,
0xCE,0x0E,0x85,0x95,0x37,0x6A,0xED,0x09,0xB6,0xAE,0x67,0xCD,0x51,0x64,0x9F,0xC6,
0x5C,0xD1,0xBC,0x57,0x6E,0x67,0x35,0x80,0x76,0x36,0xA4,0x87,0x81,0x6E,0x38,0x8F,
0xD8,0x2B,0x15,0x4E,0x7B,0x25,0xD8,0x5A,0xBF,0x4E,0x83,0xC1,0x8D,0xD2,0x93,0xD5,
0x1A,0x71,0xB5,0x60,0x9C,0x9D,0x33,0x4E,0x55,0xF9,0x12,0x58,0x0C,0x86,0xB8,0x16,
0x0D,0xC1,0xE5,0x77,0x45,0x8D,0x50,0x48,0xBA,0x2B,0x2D,0xE4,0x94,0x85,0xE1,0xE8,
0xC4,0x9D,0xC6,0x68,0xA5,0xB0,0xA3,0xFC,0x67,0x7E,0x70,0xBA,0x02,0x59,0x4B,0x77,
0x42,0x91,0x39,0xB9,0xF5,0xCD,0xE1,0x4C,0xEF,0xC0,0x3B,0x48,0x8C,0xA6,0xE5,0x21,
0x5D,0xFD,0x6A,0x6A,0xBB,0xA7,0x16,0x35,0x60,0xD2,0xE6,0xAD,0xF3,0x46,0x29,0xC9,
0xE8,0xC3,0x8B,0xE9,0x79,0xC0,0x6A,0x61,0x67,0x15,0xB2,0xF0,0xFD,0xE5,0x68,0xBC,
0x62,0x5F,0x6E,0xCF,0x99,0xDD,0xEF,0x1B,0x63,0xFE,0x92,0x65,0xAB,0x02,0x03,0x01,
0x00,0x01,0xA3,0x81,0xAE,0x30,0x81,0xAB,0x30,0x0E,0x06,0x03,0x55,0x1D,0x0F,0x01,
0x01,0xFF,0x04,0x04,0x03,0x02,0x01,0x86,0x30,0x0F,0x06,0x03,0x55,0x1D,0x13,0x01,
0x01,0xFF,0x04,0x05,0x30,0x03,0x01,0x01,0xFF,0x30,0x1D,0x06,0x03,0x55,0x1D,0x0E,
0x04,0x16,0x04,0x14,0x88,0x27,0x17,0x09,0xA9,0xB6,0x18,0x60,0x8B,0xEC,0xEB,0xBA,
0xF6,0x47,0x59,0xC5,0x52,0x54,0xA3,0xB7,0x30,0x1F,0x06,0x03,0x55,0x1D,0x23,0x04,
0x18,0x30,0x16,0x80,0x14,0x2B,0xD0,0x69,0x47,0x94,0x76,0x09,0xFE,0xF4,0x6B,0x8D,
0x2E,0x40,0xA6,0xF7,0x47,0x4D,0x7F,0x08,0x5E,0x30,0x36,0x06,0x03,0x55,0x1D,0x1F,
0x04,0x2F,0x30,0x2D,0x30,0x2B,0xA0,0x29,0xA0,0x27,0x86,0x25,0x68,0x74,0x74,0x70,
0x3A,0x2F,0x2F,0x77,0x77,0x77,0x2E,0x61,0x70,0x70,0x6C,0x65,0x2E,0x63,0x6F,0x6D,
0x2F,0x61,0x70,0x70,0x6C,0x65,0x63,0x61,0x2F,0x72,0x6F,0x6F,0x74,0x2E,0x63,0x72,
0x6C,0x30,0x10,0x06,0x0A,0x2A,0x86,0x48,0x86,0xF7,0x63,0x64,0x06,0x02,0x01,0x04,
0x02,0x05,0x00,0x30,0x0D,0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,0x05,
0x05,0x00,0x03,0x82,0x01,0x01,0x00,0xDA,0x32,0x00,0x96,0xC5,0x54,0x94,0xD3,0x3B,
0x82,0x37,0x66,0x7D,0x2E,0x68,0xD5,0xC3,0xC6,0xB8,0xCB,0x26,0x8C,0x48,0x90,0xCF,
0x13,0x24,0x6A,0x46,0x8E,0x63,0xD4,0xF0,0xD0,0x13,0x06,0xDD,0xD8,0xC4,0xC1,0x37,
0x15,0xF2,0x33,0x13,0x39,0x26,0x2D,0xCE,0x2E,0x55,0x40,0xE3,0x0B,0x03,0xAF,0xFA,
0x12,0xC2,0xE7,0x0D,0x21,0xB8,0xD5,0x80,0xCF,0xAC,0x28,0x2F,0xCE,0x2D,0xB3,0x4E,
0xAF,0x86,0x19,0x04,0xC6,0xE9,0x50,0xDD,0x4C,0x29,0x47,0x10,0x23,0xFC,0x6C,0xBB,
0x1B,0x98,0x6B,0x48,0x89,0xE1,0x5B,0x9D,0xDE,0x46,0xDB,0x35,0x85,0x35,0xEF,0x3E,
0xD0,0xE2,0x58,0x4B,0x38,0xF4,0xED,0x75,0x5A,0x1F,0x5C,0x70,0x1D,0x56,0x39,0x12,
0xE5,0xE1,0x0D,0x11,0xE4,0x89,0x25,0x06,0xBD,0xD5,0xB4,0x15,0x8E,0x5E,0xD0,0x59,
0x97,0x90,0xE9,0x4B,0x81,0xE2,0xDF,0x18,0xAF,0x44,0x74,0x1E,0x19,0xA0,0x3A,0x47,
0xCC,0x91,0x1D,0x3A,0xEB,0x23,0x5A,0xFE,0xA5,0x2D,0x97,0xF7,0x7B,0xBB,0xD6,0x87,
0x46,0x42,0x85,0xEB,0x52,0x3D,0x26,0xB2,0x63,0xA8,0xB4,0xB1,0xCA,0x8F,0xF4,0xCC,
0xE2,0xB3,0xC8,0x47,0xE0,0xBF,0x9A,0x59,0x83,0xFA,0xDA,0x98,0x53,0x2A,0x82,0xF5,
0x7C,0x65,0x2E,0x95,0xD9,0x33,0x5D,0xF5,0xED,0x65,0xCC,0x31,0x37,0xC5,0x5A,0x04,
0xE8,0x6B,0xE1,0xE7,0x88,0x03,0x4A,0x75,0x9E,0x9B,0x28,0xCB,0x4A,0x40,0x88,0x65,
0x43,0x75,0xDD,0xCB,0x3A,0x25,0x23,0xC5,0x9E,0x57,0xF8,0x2E,0xCE,0xD2,0xA9,0x92,
0x5E,0x73,0x2E,0x2F,0x25,0x75,0x15,
};

/* TODO: Use the shared version of this function in print_cert.c. */
#if !TARGET_OS_IPHONE
__unused
#endif
static void print_line(CFStringRef line) {
    UInt8 buf[256];
    CFRange range = { .location = 0 };
    range.length = CFStringGetLength(line);
    while (range.length > 0) {
        CFIndex bytesUsed = 0;
        CFIndex converted = CFStringGetBytes(line, range, kCFStringEncodingUTF8, 0, false, buf, sizeof(buf), &bytesUsed);
        fwrite(buf, 1, bytesUsed, stdout);
        range.length -= converted;
        range.location += converted;
    }
    fputc('\n', stdout);
}

#if !TARGET_OS_IPHONE
__unused
#endif
static void printPlist(CFArrayRef plist, CFIndex indent, CFIndex maxWidth) {
    CFIndex count = CFArrayGetCount(plist);
    CFIndex ix;
    for (ix = 0; ix < count ; ++ix) {
        CFDictionaryRef prop = (CFDictionaryRef)CFArrayGetValueAtIndex(plist,
            ix);
        CFStringRef pType = (CFStringRef)CFDictionaryGetValue(prop,
            kSecPropertyKeyType);
        CFStringRef label = (CFStringRef)CFDictionaryGetValue(prop,
            kSecPropertyKeyLabel);
        CFStringRef llabel = (CFStringRef)CFDictionaryGetValue(prop,
            kSecPropertyKeyLocalizedLabel);
        CFTypeRef value = (CFTypeRef)CFDictionaryGetValue(prop,
            kSecPropertyKeyValue);

        bool isSection = CFEqual(pType, kSecPropertyTypeSection);
        CFMutableStringRef line = CFStringCreateMutable(NULL, 0);
        CFIndex jx = 0;
        for (jx = 0; jx < indent; ++jx) {
            CFStringAppend(line, CFSTR("    "));
        }
        if (llabel) {
            CFStringAppend(line, llabel);
            if (!isSection) {
                for (jx = CFStringGetLength(llabel) + indent * 4;
                    jx < maxWidth; ++jx) {
                    CFStringAppend(line, CFSTR(" "));
                }
                CFStringAppend(line, CFSTR(" : "));
            }
        }
        if (CFEqual(pType, kSecPropertyTypeWarning)) {
            CFStringAppend(line, CFSTR("*WARNING* "));
            CFStringAppend(line, (CFStringRef)value);
        } else if (CFEqual(pType, kSecPropertyTypeError)) {
            CFStringAppend(line, CFSTR("*ERROR* "));
            CFStringAppend(line, (CFStringRef)value);
        } else if (CFEqual(pType, kSecPropertyTypeSuccess)) {
            CFStringAppend(line, CFSTR("*OK* "));
            CFStringAppend(line, (CFStringRef)value);
        } else if (CFEqual(pType, kSecPropertyTypeTitle)) {
            CFStringAppend(line, CFSTR("*"));
            CFStringAppend(line, (CFStringRef)value);
            CFStringAppend(line, CFSTR("*"));
        } else if (CFEqual(pType, kSecPropertyTypeSection)) {
        } else if (CFEqual(pType, kSecPropertyTypeData)) {
            CFDataRef data = (CFDataRef)value;
            CFIndex length = CFDataGetLength(data);
            if (length > 20)
                CFStringAppendFormat(line, NULL, CFSTR("[%" PRIdCFIndex " bytes] "), length);
            const UInt8 *bytes = CFDataGetBytePtr(data);
            for (jx = 0; jx < length; ++jx) {
                if (jx == 0)
                    CFStringAppendFormat(line, NULL, CFSTR("%02X"), bytes[jx]);
                else if (jx < 15 || length <= 20)
                    CFStringAppendFormat(line, NULL, CFSTR(" %02X"),
                        bytes[jx]);
                else {
                    CFStringAppend(line, CFSTR(" ..."));
                    break;
                }
            }
        } else if (CFEqual(pType, kSecPropertyTypeString)) {
            CFStringAppend(line, (CFStringRef)value);
        } else if (CFEqual(pType, kSecPropertyTypeDate)) {
            CFLocaleRef lc = CFLocaleCopyCurrent();
            CFDateFormatterRef df = CFDateFormatterCreate(NULL, lc,
                kCFDateFormatterFullStyle, kCFDateFormatterFullStyle);
            //CFTimeZoneRef tz = CFTimeZoneCreateWithName(NULL, CFSTR("GMT"), false);
            //CFDateFormatterSetProperty(df, kCFDateFormatterTimeZone, tz);
            //CFRelease(tz);
            CFDateRef date = (CFDateRef)value;
            CFStringRef ds = CFDateFormatterCreateStringWithDate(NULL, df,
                date);
            CFStringAppend(line, ds);
            CFRelease(ds);
            CFRelease(df);
            CFRelease(lc);
        } else if (CFEqual(pType, kSecPropertyTypeURL)) {
            CFURLRef url = (CFURLRef)value;
            CFStringAppend(line, CFSTR("<"));
            CFStringAppend(line, CFURLGetString(url));
            CFStringAppend(line, CFSTR(">"));
        } else {
            CFStringAppendFormat(line, NULL, CFSTR("*unknown type %@* = %@"),
            pType, value);
        }

		if (!isSection || label)
			print_line(line);
		CFRelease(line);
        if (isSection) {
            printPlist((CFArrayRef)value, indent + 1, maxWidth);
        }
    }
}

#if !TARGET_OS_IPHONE
__unused
#endif
static CFIndex maxLabelWidth(CFArrayRef plist, CFIndex indent) {
    CFIndex count = CFArrayGetCount(plist);
    CFIndex ix;
    CFIndex maxWidth = 0;
    for (ix = 0; ix < count ; ++ix) {
        CFDictionaryRef prop = (CFDictionaryRef)CFArrayGetValueAtIndex(plist,
            ix);
        CFStringRef pType = (CFStringRef)CFDictionaryGetValue(prop,
            kSecPropertyKeyType);
        CFStringRef llabel = (CFStringRef)CFDictionaryGetValue(prop,
            kSecPropertyKeyLocalizedLabel);
        CFTypeRef value = (CFTypeRef)CFDictionaryGetValue(prop,
            kSecPropertyKeyValue);

        if (CFEqual(pType, kSecPropertyTypeSection)) {
            CFIndex width = maxLabelWidth((CFArrayRef)value, indent + 1);
            if (width > maxWidth)
                maxWidth = width;
        } else if (llabel) {
            CFIndex width = indent * 4 + CFStringGetLength(llabel);
            if (width > maxWidth)
                maxWidth = width;
        }
    }

    return maxWidth;
}

#if !TARGET_OS_IPHONE
__unused
#endif
static void print_plist(CFArrayRef plist) {
    if (plist)
        printPlist(plist, 0, maxLabelWidth(plist, 0));
    else
        printf("NULL plist\n");
}

#if !TARGET_OS_IPHONE
__unused
#endif
static void print_cert(SecCertificateRef cert, bool verbose) {
    CFArrayRef plist;
    if (verbose)
        plist = SecCertificateCopyProperties(cert);
    else {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        plist = SecCertificateCopySummaryProperties(cert, now);
    }

    CFStringRef subject = SecCertificateCopySubjectString(cert);
    if (subject) {
        print_line(subject);
        CFRelease(subject);
    } else {
        print_line(CFSTR("no subject"));
    }

    print_plist(plist);
    CFRelease(plist);
}

static void tests(void)
{
    SecTrustRef trust;
    SecCertificateRef leaf, wwdr_intermediate;
    SecPolicyRef policy;

    isnt(wwdr_intermediate = SecCertificateCreateWithBytes(kCFAllocatorDefault,
        wwdr_intermediate_cert, sizeof(wwdr_intermediate_cert)), NULL, "create WWDR intermediate");
    isnt(leaf = SecCertificateCreateWithBytes(kCFAllocatorDefault,
        codesigning_certificate, sizeof(codesigning_certificate)), NULL, "create leaf");

    const void *vcerts[] = { leaf, wwdr_intermediate };
    CFArrayRef certs = CFArrayCreate(kCFAllocatorDefault, vcerts, 2, NULL);

    isnt(policy = SecPolicyCreateiPhoneProfileApplicationSigning(), NULL,
        "create iPhoneProfileApplicationSigning policy instance");
    ok_status(SecTrustCreateWithCertificates(certs, policy, &trust), "create trust for leaf");
    CFDateRef verifyDate = CFDateCreate(kCFAllocatorDefault, 228244066);
    ok_status(SecTrustSetVerifyDate(trust, verifyDate), "set verify date");
    CFReleaseNull(verifyDate);
    SecTrustResultType trustResult;
    CFArrayRef properties = NULL;
    properties = SecTrustCopyProperties(trust);
#if TARGET_OS_IPHONE
    // Note: OS X will trigger the evaluation in order to return the properties.
    is(properties, NULL, "no properties returned before eval");
#endif
    CFReleaseNull(properties);
    ok_status(SecTrustEvaluate(trust, &trustResult), "evaluate trust");
    is_status(trustResult, kSecTrustResultUnspecified, "trust is kSecTrustResultUnspecified");
    properties = SecTrustCopyProperties(trust);

#if TARGET_OS_IPHONE
    if (properties) {
        print_plist(properties);
        print_cert(leaf, true);
        print_cert(wwdr_intermediate, false);
    }
#endif
    CFReleaseNull(properties);
    // verify wrapper functions are available
    properties = SecCertificateCopyProperties(leaf);
    isnt(properties, NULL, "leaf properties returned");
    CFReleaseNull(properties);
    // Xcode doesn't have a SDK for 10.15.1 so we need to work around this.
    // rdar://problem/55890533
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
    properties = SecCertificateCopyLocalizedProperties(leaf, true);
#pragma clang diagnostic pop
    isnt(properties, NULL, "localized leaf properties returned");
    CFReleaseNull(properties);

    CFReleaseNull(trust);
    CFReleaseNull(wwdr_intermediate);
    CFReleaseNull(leaf);
    CFReleaseNull(certs);
    CFReleaseNull(policy);
	CFReleaseNull(trust);
}

int si_26_sectrust_copyproperties(int argc, char *const *argv)
{
#if TARGET_OS_IPHONE
    plan_tests(10);
#else
    // <rdar://problem/26358545>
    plan_tests(9);
#endif


    tests();

    return 0;
}
