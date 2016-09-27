/*
 * Copyright (c) 2003-2006,2008,2010-2012 Apple Inc. All Rights Reserved.
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
 *
 * secErrorStr.c - ASCII string version of NSS Sec layer error codes
 */
#include "secerr.h"
#include <stdio.h>

typedef struct {
	PRErrorCode		value;
	const char 		*name;
} SecErrorNameValuePair;

/* one entry in an array of SecErrorNameValuePairs */
#define SNVP(err)		{err, #err}

/* the NULL entry which terminates the SecErrorNameValuePair list */
#define SNVP_END		{0, NULL}

static const SecErrorNameValuePair errValues[] = 
{
	/* FIXME: we really don't need all of these, but they're not 
	 * compiled for NDEBUG builds. */
	#ifndef	NDEBUG
	SNVP(SEC_ERROR_IO),
	SNVP(SEC_ERROR_LIBRARY_FAILURE),
	SNVP(SEC_ERROR_BAD_DATA 	),
	SNVP(SEC_ERROR_OUTPUT_LEN),
	SNVP(SEC_ERROR_INPUT_LEN),
	SNVP(SEC_ERROR_INVALID_ARGS),
	SNVP(SEC_ERROR_INVALID_ALGORITHM),
	SNVP(SEC_ERROR_INVALID_AVA),
	SNVP(SEC_ERROR_INVALID_TIME),
	SNVP(SEC_ERROR_BAD_DER),
	SNVP(SEC_ERROR_BAD_SIGNATURE ),
	SNVP(SEC_ERROR_EXPIRED_CERTIFICATE),
	SNVP(SEC_ERROR_REVOKED_CERTIFICATE),
	SNVP(SEC_ERROR_UNKNOWN_ISSUER ),
	SNVP(SEC_ERROR_BAD_KEY),
	SNVP(SEC_ERROR_BAD_PASSWORD),
	SNVP(SEC_ERROR_RETRY_PASSWORD),
	SNVP(SEC_ERROR_NO_NODELOCK ),
	SNVP(SEC_ERROR_BAD_DATABASE),
	SNVP(SEC_ERROR_NO_MEMORY),
	SNVP(SEC_ERROR_UNTRUSTED_ISSUER),
	SNVP(SEC_ERROR_UNTRUSTED_CERT),
	SNVP(SEC_ERROR_DUPLICATE_CERT),
	SNVP(SEC_ERROR_DUPLICATE_CERT_NAME),
	SNVP(SEC_ERROR_ADDING_CERT),
	SNVP(SEC_ERROR_FILING_KEY),
	SNVP(SEC_ERROR_NO_KEY),
	SNVP(SEC_ERROR_CERT_VALID),
	SNVP(SEC_ERROR_CERT_NOT_VALID),
	SNVP(SEC_ERROR_CERT_NO_RESPONSE),
	SNVP(SEC_ERROR_EXPIRED_ISSUER_CERTIFICATE),
	SNVP(SEC_ERROR_CRL_EXPIRED),
	SNVP(SEC_ERROR_CRL_BAD_SIGNATURE),
	SNVP(SEC_ERROR_CRL_INVALID),
	SNVP(SEC_ERROR_EXTENSION_VALUE_INVALID),
	SNVP(SEC_ERROR_EXTENSION_NOT_FOUND),
	SNVP(SEC_ERROR_CA_CERT_INVALID),
	SNVP(SEC_ERROR_PATH_LEN_CONSTRAINT_INVALID),
	SNVP(SEC_ERROR_CERT_USAGES_INVALID),
	SNVP(SEC_INTERNAL_ONLY),
	SNVP(SEC_ERROR_INVALID_KEY),
	SNVP(SEC_ERROR_UNKNOWN_CRITICAL_EXTENSION),
	SNVP(SEC_ERROR_OLD_CRL),
	SNVP(SEC_ERROR_NO_EMAIL_CERT),
	SNVP(SEC_ERROR_NO_RECIPIENT_CERTS_QUERY),
	SNVP(SEC_ERROR_NOT_A_RECIPIENT),
	SNVP(SEC_ERROR_PKCS7_KEYALG_MISMATCH),
	SNVP(SEC_ERROR_PKCS7_BAD_SIGNATURE),
	SNVP(SEC_ERROR_UNSUPPORTED_KEYALG),
	SNVP(SEC_ERROR_DECRYPTION_DISALLOWED),
	SNVP(XP_SEC_FORTEZZA_BAD_CARD),
	SNVP(XP_SEC_FORTEZZA_NO_CARD),
	SNVP(XP_SEC_FORTEZZA_NONE_SELECTED ),
	SNVP(XP_SEC_FORTEZZA_MORE_INFO ),
	SNVP(XP_SEC_FORTEZZA_PERSON_NOT_FOUND ),
	SNVP(XP_SEC_FORTEZZA_NO_MORE_INFO),
	SNVP(XP_SEC_FORTEZZA_BAD_PIN),
	SNVP(XP_SEC_FORTEZZA_PERSON_ERROR),
	SNVP(SEC_ERROR_NO_KRL),
	SNVP(SEC_ERROR_KRL_EXPIRED),
	SNVP(SEC_ERROR_KRL_BAD_SIGNATURE),
	SNVP(SEC_ERROR_REVOKED_KEY ),
	SNVP(SEC_ERROR_KRL_INVALID),
	SNVP(SEC_ERROR_NEED_RANDOM),
	SNVP(SEC_ERROR_NO_MODULE),
	SNVP(SEC_ERROR_NO_TOKEN),
	SNVP(SEC_ERROR_READ_ONLY),
	SNVP(SEC_ERROR_NO_SLOT_SELECTED),
	SNVP(SEC_ERROR_CERT_NICKNAME_COLLISION),
	SNVP(SEC_ERROR_KEY_NICKNAME_COLLISION),
	SNVP(SEC_ERROR_SAFE_NOT_CREATED),
	SNVP(SEC_ERROR_BAGGAGE_NOT_CREATED),
	SNVP(XP_JAVA_REMOVE_PRINCIPAL_ERROR),
	SNVP(XP_JAVA_DELETE_PRIVILEGE_ERROR),
	SNVP(XP_JAVA_CERT_NOT_EXISTS_ERROR ),
	SNVP(SEC_ERROR_BAD_EXPORT_ALGORITHM),
	SNVP(SEC_ERROR_EXPORTING_CERTIFICATES),
	SNVP(SEC_ERROR_IMPORTING_CERTIFICATES),
	SNVP(SEC_ERROR_PKCS12_DECODING_PFX),
	SNVP(SEC_ERROR_PKCS12_INVALID_MAC),
	SNVP(SEC_ERROR_PKCS12_UNSUPPORTED_MAC_ALGORITHM),
	SNVP(SEC_ERROR_PKCS12_UNSUPPORTED_TRANSPORT_MODE),
	SNVP(SEC_ERROR_PKCS12_CORRUPT_PFX_STRUCTURE),
	SNVP(SEC_ERROR_PKCS12_UNSUPPORTED_PBE_ALGORITHM),
	SNVP(SEC_ERROR_PKCS12_UNSUPPORTED_VERSION ),
	SNVP(SEC_ERROR_PKCS12_PRIVACY_PASSWORD_INCORRECT),
	SNVP(SEC_ERROR_PKCS12_CERT_COLLISION),
	SNVP(SEC_ERROR_USER_CANCELLED),
	SNVP(SEC_ERROR_PKCS12_DUPLICATE_DATA),
	SNVP(SEC_ERROR_MESSAGE_SEND_ABORTED),
	SNVP(SEC_ERROR_INADEQUATE_KEY_USAGE),
	SNVP(SEC_ERROR_INADEQUATE_CERT_TYPE),
	SNVP(SEC_ERROR_CERT_ADDR_MISMATCH),
	SNVP(SEC_ERROR_PKCS12_UNABLE_TO_IMPORT_KEY),
	SNVP(SEC_ERROR_PKCS12_IMPORTING_CERT_CHAIN),
	SNVP(SEC_ERROR_PKCS12_UNABLE_TO_LOCATE_OBJECT_BY_NAME),
	SNVP(SEC_ERROR_PKCS12_UNABLE_TO_EXPORT_KEY),
	SNVP(SEC_ERROR_PKCS12_UNABLE_TO_WRITE),
	SNVP(SEC_ERROR_PKCS12_UNABLE_TO_READ),
	SNVP(SEC_ERROR_PKCS12_KEY_DATABASE_NOT_INITIALIZED),
	SNVP(SEC_ERROR_KEYGEN_FAIL),
	SNVP(SEC_ERROR_INVALID_PASSWORD),
	SNVP(SEC_ERROR_RETRY_OLD_PASSWORD),
	SNVP(SEC_ERROR_BAD_NICKNAME),
	SNVP(SEC_ERROR_NOT_FORTEZZA_ISSUER),
	SNVP(SEC_ERROR_CANNOT_MOVE_SENSITIVE_KEY),
	SNVP(SEC_ERROR_JS_INVALID_MODULE_NAME),
	SNVP(SEC_ERROR_JS_INVALID_DLL),
	SNVP(SEC_ERROR_JS_ADD_MOD_FAILURE),
	SNVP(SEC_ERROR_JS_DEL_MOD_FAILURE),
	SNVP(SEC_ERROR_OLD_KRL),
	SNVP(SEC_ERROR_CKL_CONFLICT),
	SNVP(SEC_ERROR_CERT_NOT_IN_NAME_SPACE),
	SNVP(SEC_ERROR_KRL_NOT_YET_VALID),
	SNVP(SEC_ERROR_CRL_NOT_YET_VALID),
	SNVP(SEC_ERROR_UNKNOWN_CERT),
	SNVP(SEC_ERROR_UNKNOWN_SIGNER),
	SNVP(SEC_ERROR_CERT_BAD_ACCESS_LOCATION ),
	SNVP(SEC_ERROR_OCSP_UNKNOWN_RESPONSE_TYPE),
	SNVP(SEC_ERROR_OCSP_BAD_HTTP_RESPONSE),
	SNVP(SEC_ERROR_OCSP_MALFORMED_REQUEST),
	SNVP(SEC_ERROR_OCSP_SERVER_ERROR),
	SNVP(SEC_ERROR_OCSP_TRY_SERVER_LATER),
	SNVP(SEC_ERROR_OCSP_REQUEST_NEEDS_SIG),
	SNVP(SEC_ERROR_OCSP_UNAUTHORIZED_REQUEST),
	SNVP(SEC_ERROR_OCSP_UNKNOWN_RESPONSE_STATUS),
	SNVP(SEC_ERROR_OCSP_UNKNOWN_CERT),
	SNVP(SEC_ERROR_OCSP_NOT_ENABLED),
	SNVP(SEC_ERROR_OCSP_NO_DEFAULT_RESPONDER),
	SNVP(SEC_ERROR_OCSP_MALFORMED_RESPONSE ),
	SNVP(SEC_ERROR_OCSP_UNAUTHORIZED_RESPONSE),
	SNVP(SEC_ERROR_OCSP_FUTURE_RESPONSE ),
	SNVP(SEC_ERROR_OCSP_OLD_RESPONSE),
	SNVP(SEC_ERROR_DIGEST_NOT_FOUND),
	SNVP(SEC_ERROR_UNSUPPORTED_MESSAGE_TYPE),
	SNVP(SEC_ERROR_MODULE_STUCK),
	SNVP(SEC_ERROR_BAD_TEMPLATE),
	SNVP(SEC_ERROR_CRL_NOT_FOUND),
	SNVP(SEC_ERROR_REUSED_ISSUER_AND_SERIAL ),
	SNVP(SEC_ERROR_BUSY),
	#endif	/* NDEBUG */
	SNVP_END
};

/* 
 * Given a PRErrorCode, obtain a const C string. Not copied, not
 * to be freed by caller.
 */
const char *SECErrorString(PRErrorCode err)
{
 	static char badStr[100];
	const SecErrorNameValuePair *nvp = errValues;
	
	while(nvp->name != NULL) {
		if(nvp->value == err) {
			return nvp->name;
		}
		nvp++;
	}
	
	/* Not found, not thread safe */
	sprintf(badStr, "UNKNOWN (%d(d)", err);
	return badStr;
	
}
