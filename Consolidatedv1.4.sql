--------------------------------------------------------
-- Filename:        "Consolidatedv1.3.sql"
-- Version:         v1.0, 2026-06-26 Created
--                  v1.1, 2026-06-29 PSP, Added additional parameters
--                  v1.2, 2026-06-30 PSP, Removed usage of Argus 8.2.3+ views (v$lm_formulation_edqm, G_K_4_R_9_2B) and use of ESM_MAPPING_UTL.F_GET_MEDICINALPRODUCT (G_K_2_2).
--                                        Updated index script on HALO_LOG to create index only (Do not add PK as it already exists)  
--                  v1.3, 2026-07-10 PSP, Update case classification config (inclusion of vifor)


-- Purpose:         Deployment of CSL specific Argus-HaloPV adaptor database objects for HaloPV 6.
-- Instructions:    1. Paste the script into SQL Developer. You must be logged into the target Argus database with a user having access to the HALO_STAGE schema
--                  2. Execute the script (F5 / Run as script) - provide environment specific values when prompted.
--------------------------------------------------------

alter session set current_schema = HALO_STAGE;

--------------------------------------------------------
--  Configuration updates
--------------------------------------------------------
declare
 c number;
begin
    
    select count(1) into c from HALO_CONFIG where parameter = 'EXCLUDE_ATTACHMENT_TYPE';
 
    if c = 0 then 
        Insert into HALO_CONFIG (PARAMETER,VALUE,POSSIBLE_VALUES,COMMENTS) values ('EXCLUDE_ATTACHMENT_TYPE',null,null,'Add atachment type to exclude transmission. ONE TIME CONFIGURATION.');
    end if;
 
    select count(1) into c from HALO_CONFIG where parameter = 'SEND_ATTACHMENT';

    if c = 0 then 
        Insert into HALO_CONFIG (PARAMETER,VALUE,POSSIBLE_VALUES,COMMENTS) values ('SEND_ATTACHMENT','0','0,1','1 - Send Attachments, 0 - Do not send Attachments');
    end if;
    
    select count(1) into c from HALO_CONFIG where parameter = 'AUTH_HASH_KEY';

    if c = 0 then 
        Insert into HALO_CONFIG (PARAMETER,VALUE,POSSIBLE_VALUES,COMMENTS) values ('AUTH_HASH_KEY',null,null,'We will generate the hash key from the hash key generation proc');
    end if;
    
    select count(1) into c from HALO_CONFIG where parameter = 'AUTH_SECRET_KEY';

    if c = 0 then 
        Insert into HALO_CONFIG (PARAMETER,VALUE,POSSIBLE_VALUES,COMMENTS) values ('AUTH_SECRET_KEY','&AUTH_SECRET_KEY',null,'We will use this secret key in hash generation proc');
    end if;
    
    select count(1) into c from HALO_CONFIG where parameter = 'AUTH_TENANT_ID';

    if c = 0 then 
        Insert into HALO_CONFIG (PARAMETER,VALUE,POSSIBLE_VALUES,COMMENTS) values ('AUTH_TENANT_ID','&AUTH_TENANT_ID',null,'We will use this tenant id in hash generation proc');
    end if;
    
    select count(1) into c from HALO_CONFIG where parameter = 'AUTH_TIMESTAMP';

    if c = 0 then 
        Insert into HALO_CONFIG (PARAMETER,VALUE,POSSIBLE_VALUES,COMMENTS) values ('AUTH_TIMESTAMP',null,null,'This date is used in hash generation function');
    end if;
    
    select count(1) into c from HALO_CONFIG where parameter = 'HALO_VERSION';

    if c = 0 then 
        Insert into HALO_CONFIG (PARAMETER,VALUE,POSSIBLE_VALUES,COMMENTS) values ('HALO_VERSION','6',null,'Contains the HALO Major Version (Integer Form).');
    end if;
     
     
    -- Existing configuration steps
    UPDATE HALO_CONFIG
    SET VALUE='&HALO_AUTHORIZATION'
    WHERE PARAMETER='HALO_AUTHORIZATION';

    UPDATE HALO_CONFIG
    SET VALUE='&HALO_PRODUCT_CONFIG_WEBSERVICE'
    WHERE PARAMETER='HALO_PRODUCT_CONFIG_WEBSERVICE';

    UPDATE HALO_CONFIG
    SET VALUE='&HALO_AGREEMENT_CONFIG_WEBSERVICE'
    WHERE PARAMETER='HALO_AGREEMENT_CONFIG_WEBSERVICE';

    UPDATE HALO_CONFIG
    SET VALUE='&HALO_ORGANIZATION_CONFIG_WEBSERVICE'
    WHERE PARAMETER='HALO_ORGANIZATION_CONFIG_WEBSERVICE';

    UPDATE HALO_CONFIG
    SET VALUE='&ARGUS_ICSR_R3_WEBSERVICE'
    WHERE PARAMETER='ARGUS_ICSR_R3_WEBSERVICE';

    UPDATE HALO_CONFIG
    SET VALUE='&WALLET_PATH'
    WHERE PARAMETER='WALLET_PATH';

    -- Classification updates (change vifor from exclude to include)

    UPDATE halo_config
	SET parameter = 'ICSR_DATA_TRANSFER_INCLUDE_ARGUS_CLASSIFICATIONS',
	Comments = 'Argus classifications to include in ICSR Data Transfer'
    WHERE lower(value) = 'vifor';

 
    commit;
end;
/
 
 
-- No more user provided parameters 
set define off;


--------------------------------------------------------
--  Drop obsolete objects
--------------------------------------------------------

DROP PROCEDURE "HALO_ICSR_DATA_TRANSFER_JOB_TEMP";

--------------------------------------------------------
--  DDL for Table HALO_TRANSFER_ATTACHMENT
--------------------------------------------------------

  CREATE TABLE HALO_TRANSFER_ATTACHMENT
   (	"CASE_ID" NUMBER(12, 0), 
	"SEQ_NUM" NUMBER, 
	"LAST_TRANFER_TIME" DATE, 
	"STATUS" NUMBER
   ) SEGMENT CREATION IMMEDIATE 
  PCTFREE 10 PCTUSED 40 INITRANS 1 MAXTRANS 255 
 NOCOMPRESS LOGGING
  STORAGE(INITIAL 65536 NEXT 1048576 MINEXTENTS 1 MAXEXTENTS 2147483645
  PCTINCREASE 0 FREELISTS 1 FREELIST GROUPS 1
  BUFFER_POOL DEFAULT FLASH_CACHE DEFAULT CELL_FLASH_CACHE DEFAULT)
  TABLESPACE "USERS1"; 
  
--------------------------------------------------------
--  Indexes
--------------------------------------------------------
CREATE INDEX LOG_ID ON HALO_LOG (LOG_ID);

--------------------------------------------------------------
-- GET_MP_JSON_BY_PK
--------------------------------------------------------------

CREATE OR REPLACE FUNCTION GET_MP_JSON_BY_PK (
    m_mp_id IN NUMBER
) RETURN CLOB IS
/******************************************************************************************************
--  Purpose              : Fetching product export data from Argus database
--  Input                : N/A (all products are transferred)
--  Changes:             : Created, Praveen Gupta, 19-Jul-2022
						 : Issue fixing Sudarshan Hegde, 14-Sep-2022 - HLP-2289
						 : CSL Custom deployment. Updated OWNER_ORG_CODE and reverted product_id to manufacturer_id, PSP, 25-Jun-2026 
******************************************************************************************************/
    v_result       CLOB;
    l_source       VARCHAR2(100);
    v_last_run     DATE;
    v_entity_name  VARCHAR2(100) := 'PRODUCT';
    v_halo_char_id VARCHAR2(200) := NULL;
BEGIN

    --halo_write_error_log('GET_MP_JSON_BY_PK '|| 'BEGIN m_MP_ID=' || m_MP_ID);
    halo_write_log('GET_MP_JSON_BY_PK', 'INFO', 'GET_MP_JSON_BY_PK '
                                                || 'BEGIN m_MP_ID='
                                                || m_mp_id);
    SELECT
        halo_char_id
    INTO l_source
    FROM
        stg_argus_halo_idmap
    WHERE
        entity_name = 'SOURCES';

    BEGIN
        SELECT
            halo_char_id
        INTO v_halo_char_id
        FROM
            stg_argus_halo_idmap
        WHERE
                entity_name = v_entity_name
            AND argus_id = m_mp_id;
            

    EXCEPTION
        WHEN OTHERS THEN
            v_halo_char_id := NULL;
            halo_write_log(v_entity_name, 'ERROR', 'GET_MP_JSON_BY_PK:  V_HALO_CHAR_ID IS NULL FOR ARGUS_ID:' || m_mp_id);
    END;

    SELECT
        JSON_OBJECT(
            'HALO_CODE' VALUE nvl2(v_halo_char_id, v_halo_char_id, ''),
                    'OPERATION_TYPE' VALUE
                CASE
                    WHEN(lpro.deleted IS NOT NULL
                         AND v_halo_char_id IS NOT NULL) THEN
                        '5'
                    WHEN v_halo_char_id IS NOT NULL THEN
                        '2'
                    ELSE
                        '1'
                END,
                    'HALO_CODE_MP_GROUP' VALUE(
                SELECT
                    MIN(halo_char_id)
                FROM
                    stg_argus_halo_idmap
                WHERE
                        entity_name = 'PRODUCT_FAMILY'
                    AND argus_id = lpro.family_id
            ),
                    'HALO_CODE_SOURCE' VALUE l_source,
                    'PRODUCT_TYPE_CODE' VALUE 'MEDICINE',
                    'AUTH_TYPE_CODE' VALUE 'AUTH',--DECODE(LICENSE_TYPE_ID, 1, 'INV',2,'INV',3,'INV',4,'AUTH',5,'AUTH',6,'AUTH'),
                    'SENDER_LOCAL_CODE' VALUE lpro.product_id,
                    'PRODUCT_CODE' VALUE lpro.drug_code,
                    'FULL_NAME' VALUE lpro.prod_name,
                    'STRENGTH_PART' VALUE lpro.concentration,
                    'PHARM_FORM_PART' VALUE '',
                    'FORMULATION_PART' VALUE '',
                    'TRADEMARK_NAME_PART' VALUE '',
                    'PRODUCT_OTHER_NAME' VALUE lpro.model_no,
                    'PRODUCT_SHORT_NAME' VALUE lpro.prod_name_abbrv,
                    'PRODUCT_GENERIC_NAME' VALUE lpro.prod_generic_name,
                    'COMMENT_PRODUCT' VALUE lpro.comments,
                    'EFFECTIVE_DATE' VALUE to_char(lpro.intl_birth_date, 'dd-mm-yyyy'),
                    'PRODUCT_COMPANY_NAME' VALUE(
                SELECT
                    MIN(halo_char_id)
                FROM
                    stg_argus_halo_idmap
                WHERE
                        entity_name = 'ORGANISATION'
                    AND argus_id = lpro.manufacturer_id
            ),
                    'COUNTRY_ISO2_CODE' VALUE NULL,
                    'OWNER_ORG_CODE' VALUE 'ORG35187',
            --'NAMES' VALUE NVL(GET_MP_NAMES_JSON (m_MP_ID => MP.MPD_MP_ID), '[ ]') FORMAT JSON,
            --'MPIDS' VALUE NVL(GET_MP_MPIDS_JSON (p_MP_ID => m_MP_ID), '[ ]') FORMAT JSON,
            --'PREV_DEV_PRDS' VALUE NVL(GET_MP_PREV_DEV_PRD_JSON (m_MP_ID => MP.MPD_MP_ID), '[ ]') FORMAT JSON,
                    'MP_INDS' VALUE nvl(
                get_mp_ind_json(p_mp_id => m_mp_id),
                '[ ]'
            )
        FORMAT JSON,
            --'MP_ATC' VALUE NVL(GET_MP_ATC_JSON (m_MP_ID => MP.MPD_MP_ID), '[ ]') FORMAT JSON
            --'MP_PACKAGES' VALUE NVL(GET_MP_PACKAGE_JSON (m_MP_ID => MP.MPD_MP_ID), '[ ]') FORMAT JSON,
                    'MP_LICENSES' VALUE nvl(
                get_mp_licenses_json(p_mp_id => m_mp_id),
                '[ ]'
            )
        FORMAT JSON,
            --'MP_CUSTOM_FIELDS' VALUE NVL(GET_MP_CUSTOM_FIELDS_JSON (m_MP_ID => MP.MPD_MP_ID), '[ ]') FORMAT JSON
                    'MP_PPS' VALUE nvl(
                get_mp_pp_json(p_mp_id => m_mp_id),
                '[ ]'
            )
        FORMAT JSON RETURNING CLOB)
    INTO v_result
    FROM
        lm_product lpro
    WHERE
        lpro.product_id = m_mp_id;

    RETURN v_result;
EXCEPTION
    WHEN OTHERS THEN
         -- Log Error
        halo_write_log('GET_MP_JSON_BY_PK',
                       'ERROR',
                       'GET_MP_JSON_BY_PK'
                       || 'Unhandled exception: '
                       || sqlerrm
                       || chr(13)
                       || chr(10)
                       || dbms_utility.format_error_backtrace());
         --halo_write_error_log ('GET_MP_JSON_BY_PK'|| 'Unhandled exception: ' || SQLERRM || CHR (13) || CHR (10) || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE());

         -- Make the caller aware
        RAISE;
END GET_MP_JSON_BY_PK;
/

--------------------------------------------------------------
-- GET_GRP_MP_JSON_LINK
--------------------------------------------------------------

CREATE OR REPLACE EDITIONABLE FUNCTION GET_GRP_MP_JSON_LINK (
    p_mp_id IN NUMBER
) RETURN CLOB IS

/******************************************************************************************************
--  Purpose              : Linking Family and Product data into HALO
--  Input                : N/A (all products are transferred)
--  Changes:             : Created, Sudarshan Hegde, 14-Sep-2022 - HLP-2289
						 : Changes to handle linking seprately HLP-3083
						 : CSL custom deployment. Updated owner_org_code, PSP, 2026-Jun-25 

******************************************************************************************************/

    v_result             CLOB;
    l_halo_code_source   VARCHAR2(200);
    v_current_date       DATE := sysdate;
    v_last_run           DATE;
    v_entity_name        VARCHAR2(100) := 'PRODUCT';
    v_family_entity_name VARCHAR2(100) := 'PRODUCT_FAMILY';
BEGIN
    halo_write_log('GET_GRP_MP_JSON_LINK', 'INFO', 'GET_GRP_MP_JSON_LINK '
                                                   || 'BEGIN p_MP_ID='
                                                   || p_mp_id);
    SELECT
        halo_char_id
    INTO l_halo_code_source
    FROM
        stg_argus_halo_idmap
    WHERE
        entity_name = 'SOURCES';

      -- MPD_MP_IND
    SELECT
        JSON_OBJECT(
            'LINK_GRP_MP' VALUE JSON_ARRAYAGG(
                JSON_OBJECT(
                    'HALO_CODE_MP' VALUE
                        CASE
                            WHEN EXISTS(
                                SELECT
                                    halo_char_id
                                FROM
                                    stg_argus_halo_idmap
                                WHERE
                                        entity_name = v_entity_name
                                    AND argus_id = p_mp_id
                            ) THEN
                                (
                                    SELECT
                                        halo_char_id
                                    FROM
                                        stg_argus_halo_idmap
                                    WHERE
                                            entity_name = v_entity_name
                                        AND argus_id = p_mp_id
                                )
                            ELSE
                                ''
                        END,
                    'OPERATION_TYPE' VALUE
                        CASE
                            WHEN lpro.deleted IS NULL THEN
                                8
                            ELSE
                                9
                        END,
                    'HALO_CODE_GROUP' VALUE
                        CASE
                            WHEN EXISTS(
                                SELECT
                                    halo_char_id
                                FROM
                                    stg_argus_halo_idmap
                                WHERE
                                        entity_name = v_family_entity_name
                                    AND argus_id = lpro.family_id
                            ) THEN
                                (
                                    SELECT
                                        halo_char_id
                                    FROM
                                        stg_argus_halo_idmap
                                    WHERE
                                            entity_name = v_family_entity_name
                                        AND argus_id = lpro.family_id
                                )
                            ELSE
                                ''
                        END,
						'OWNER_ORG_CODE' VALUE 'ORG35187'
                RETURNING CLOB)
            RETURNING CLOB)
        RETURNING CLOB)
    INTO v_result
    FROM
        lm_product lpro
    WHERE
        lpro.product_id = p_mp_id;

    RETURN v_result;
EXCEPTION
    WHEN OTHERS THEN
         -- Log Error
        halo_write_log('GET_GRP_MP_JSON_LINK',
                       'ERROR',
                       'GET_GRP_MP_JSON_LINK'
                       || 'Unhandled exception: '
                       || sqlerrm
                       || chr(13)
                       || chr(10)
                       || dbms_utility.format_error_backtrace());
         --halo_write_error_log ('GET_GRP_MP_JSON_LINK '|| 'Unhandled exception: ' || SQLERRM || CHR (13) || CHR (10) || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE());

         -- Make the caller aware
        RAISE;
END GET_GRP_MP_JSON_LINK;
/


--------------------------------------------------------------
-- GET_MP_IND_JSON
--------------------------------------------------------------

  CREATE OR REPLACE EDITIONABLE FUNCTION GET_MP_IND_JSON (p_MP_ID IN NUMBER) RETURN CLOB IS
/******************************************************************************************************
--  Purpose              : Fetching product medra data from Argus database
--  Input                : N/A (all products are transferred)
--  Changes:             : Created, Praveen Gupta, 19-Jul-2022
						 : CSL Custom deployment. Updated OWNER_ORG_CODE, PSP, 25-Jun-2026 


******************************************************************************************************/
v_result        CLOB;
l_halo_code_source VARCHAR2(200);

BEGIN
  --halo_write_error_log('GET_MP_IND_JSON'|| 'BEGIN p_MP_ID=' || p_MP_ID);
  HALO_WRITE_LOG('GET_MP_IND_JSON','INFO','GET_MP_IND_JSON'|| 'BEGIN p_MP_ID=' || p_MP_ID);
  SELECT HALO_CHAR_ID INTO l_halo_code_source FROM STG_ARGUS_HALO_IDMAP WHERE ENTITY_NAME='SOURCES';
  -- MPD_MP_IND
  SELECT
	 JSON_ARRAYAGG (
		JSON_OBJECT (
				'MEDDRA_VERSION'        VALUE '25',
				'MEDDRA_LEVEL'          VALUE '4',
				'MEDDRA_CODE'           VALUE LP.IND_LLT_CODE,
				'SENDER_LOCAL_CODE'     VALUE LP.IND_LLT,
				'HALO_CODE_SOURCE'      VALUE l_halo_code_source,
				'OWNER_ORG_CODE'		VALUE			'ORG35187'
		   RETURNING CLOB
		   ) RETURNING CLOB
		)
        INTO  v_result
        FROM  LM_PRODUCT LP
        WHERE LP.PRODUCT_ID = p_MP_ID;

  RETURN v_result;
EXCEPTION
  WHEN OTHERS THEN
     -- Log Error
     HALO_WRITE_LOG('GET_MP_IND_JSON','ERROR','GET_MP_IND_JSON'|| 'Unhandled exception: ' || SQLERRM || CHR (13) || CHR (10) || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE());
     --halo_write_error_log ('GET_MP_IND_JSON'|| 'Unhandled exception: ' || SQLERRM || CHR (13) || CHR (10) || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE());

     -- Make the caller aware
     RAISE;
END GET_MP_IND_JSON;
/

--------------------------------------------------------------
-- GET_MP_LIC_JSON_LINK
--------------------------------------------------------------


CREATE OR REPLACE EDITIONABLE FUNCTION GET_MP_LIC_JSON_LINK (
    p_mp_id IN NUMBER
) RETURN CLOB IS

/******************************************************************************************************
--  Purpose              : Fetching licenses data from Argus database
--  Input                : N/A (all products are transferred)
--  Changes:             : Created, Praveen Gupta, 19-Jul-2022
						 : Issue fixing Sudarshan Hegde, 14-Sep-2022 - HLP-2289
						 : Changes to handle linking seprately HLP-3083
						 : CSL Custom deployment. Updated OWNER_ORG_CODE, PSP, 25-Jun-2026 

******************************************************************************************************/

    v_result           CLOB;
    l_halo_code_source VARCHAR2(200);
    v_current_date     DATE := sysdate;
    v_last_run         DATE;
    v_entity_name      VARCHAR2(100) := 'PRODUCT';
    v_lic_entity_name  VARCHAR2(100) := 'LICENSE';
BEGIN
    halo_write_log('GET_MP_LIC_JSON_LINK', 'INFO', 'GET_MP_LIC_JSON_LINK '
                                                   || 'BEGIN p_MP_ID='
                                                   || p_mp_id);
    SELECT
        halo_char_id
    INTO l_halo_code_source
    FROM
        stg_argus_halo_idmap
    WHERE
        entity_name = 'SOURCES';

      -- MPD_MP_IND
    SELECT
        JSON_OBJECT(
            'LINK_MP_LICENSE' VALUE JSON_ARRAYAGG(
                JSON_OBJECT(
                    'HALO_CODE_MP' VALUE
                        CASE
                            WHEN EXISTS(
                                SELECT
                                    halo_char_id
                                FROM
                                    stg_argus_halo_idmap
                                WHERE
                                        entity_name = v_entity_name
                                    AND argus_id = p_mp_id
                            ) THEN
                                (
                                    SELECT
                                        halo_char_id
                                    FROM
                                        stg_argus_halo_idmap
                                    WHERE
                                            entity_name = v_entity_name
                                        AND argus_id = p_mp_id
                                )
                            ELSE
                                ''
                        END,
                    'OPERATION_TYPE' VALUE
                        CASE
                            WHEN llip.deleted IS NULL THEN
                                8
                            ELSE
                                9
                        END,
                    'HALO_CODE_LICENSE' VALUE
                        CASE
                            WHEN EXISTS(
                                SELECT
                                    halo_char_id
                                FROM
                                    stg_argus_halo_idmap
                                WHERE
                                        entity_name = v_lic_entity_name
                                    AND argus_id = lic.license_id
                            ) THEN
                                (
                                    SELECT
                                        halo_char_id
                                    FROM
                                        stg_argus_halo_idmap
                                    WHERE
                                            entity_name = v_lic_entity_name
                                        AND argus_id = lic.license_id
                                )
                            ELSE
                                ''
                        END,
						'OWNER_ORG_CODE' VALUE 'ORG35187'
                RETURNING CLOB)
            RETURNING CLOB)
        RETURNING CLOB)
    INTO v_result
    FROM
        lm_license      lic,
        lm_lic_products llip,
        lm_product      lpro
    WHERE
            lic.license_id = llip.license_id
        AND llip.product_id = lpro.product_id
        AND llip.product_id = p_mp_id;

    RETURN v_result;
EXCEPTION
    WHEN OTHERS THEN
         -- Log Error
        halo_write_log('GET_MP_LIC_JSON_LINK',
                       'ERROR',
                       'GET_MP_LIC_JSON_LINK'
                       || 'Unhandled exception: '
                       || sqlerrm
                       || chr(13)
                       || chr(10)
                       || dbms_utility.format_error_backtrace());
         --halo_write_error_log ('GET_MP_LIC_JSON_LINK '|| 'Unhandled exception: ' || SQLERRM || CHR (13) || CHR (10) || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE());

         -- Make the caller aware
        RAISE;
END get_mp_lic_json_link;
/

--------------------------------------------------------------
-- GET_MP_LICENSES_JSON
--------------------------------------------------------------

CREATE OR REPLACE EDITIONABLE FUNCTION GET_MP_LICENSES_JSON (
    p_mp_id IN NUMBER
) RETURN CLOB IS

/******************************************************************************************************
--  Purpose              : Fetching licenses data from Argus database
--  Input                : N/A (all products are transferred)
--  Changes:             : Created, Praveen Gupta, 19-Jul-2022
						 : Issue fixing Sudarshan Hegde, 14-Sep-2022 - HLP-2289
						   Issue fixed HLP-2583 Sudarshan Hegde, 20-Oct-2022
   						 : CSL Custom deployment. Updated OWNER_ORG_CODE, PSP, 25-Jun-2026 

******************************************************************************************************/

    v_result           CLOB;
    l_halo_code_source VARCHAR2(200);
    v_current_date     DATE := sysdate;
    v_last_run         DATE;
    v_entity_name      VARCHAR2(100) := 'LICENSE';
BEGIN
      --halo_write_error_log('GET_MP_LICENSES_JSON '|| 'BEGIN p_MP_ID=' || p_MP_ID);
    halo_write_log('GET_MP_LICENSES_JSON', 'INFO', 'GET_MP_LICENSES_JSON '
                                                   || 'BEGIN p_MP_ID='
                                                   || p_mp_id);
    SELECT
        halo_char_id
    INTO l_halo_code_source
    FROM
        stg_argus_halo_idmap
    WHERE
        entity_name = 'SOURCES';

    BEGIN
        SELECT
            TO_DATE(value, 'DD-MM-YYYY HH24:MI:SS')
        INTO v_last_run
        FROM
            halo_config
        WHERE
            parameter = 'PRODUCT_LAST_RUN';

    EXCEPTION
        WHEN OTHERS THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Parameter for PRODUCT_LAST_RUN is not configured in HALO_CONFIG'
                                                   || sqlerrm);
    END;

      -- MPD_MP_IND
    SELECT
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'HALO_CODE' VALUE
                    CASE
                        WHEN EXISTS(
                            SELECT
                                halo_char_id
                            FROM
                                stg_argus_halo_idmap
                            WHERE
                                    entity_name = v_entity_name
                                AND argus_id = lic.license_id
                        ) THEN
                            (
                                SELECT
                                    halo_char_id
                                FROM
                                    stg_argus_halo_idmap
                                WHERE
                                        entity_name = v_entity_name
                                    AND argus_id = lic.license_id
                            )
                        ELSE
                            ''
                    END,
                        'OPERATION_TYPE' VALUE
                    CASE
                        WHEN(lic.deleted IS NOT NULL
                             AND EXISTS(
                            SELECT
                                halo_char_id
                            FROM
                                stg_argus_halo_idmap
                            WHERE
                                    entity_name = v_entity_name
                                AND argus_id = lic.license_id
                        )) THEN
                            '5'
                        WHEN EXISTS(
                            SELECT
                                halo_char_id
                            FROM
                                stg_argus_halo_idmap
                            WHERE
                                    entity_name = v_entity_name
                                AND argus_id = lic.license_id
                        ) THEN
                            '2'
                        ELSE
                            '1'
                    END,
                        'APPLICATION_NUM' VALUE '',
                        'APPLICATION_TYPE_ID' VALUE lic.app_type,
                        'AUTH_COUNTRY_CODE' VALUE cou.a2,
                        'AUTH_DATE' VALUE to_char(lic.award_date, 'dd-mm-yyyy'),
                        'AUTH_NUM' VALUE lic.lic_number,
                        'AUTH_PROCEDURE_CODE' VALUE '',
                        'AUTH_PROCEDURE' VALUE '',
                        'AUTH_PROCEDURE_START_DATE' VALUE '',
                        'AUTH_PROCEDURE_END_DATE' VALUE '',
                        'AUTH_STATUS_CODE' VALUE '',
                        'AUTH_JURISDICTION' VALUE '',
                        'TRADE_NAME' VALUE lic.trade_name,
                        'LEGAL_BASIS' VALUE '',
                        'VALIDITY_PERIOD_START_DATE' VALUE '',
                        'VALIDITY_PERIOD_END_DATE' VALUE '',
                        'EXCLUSIVITY_START_DATE' VALUE '',
                        'EXCLUSIVITY_END_DATE' VALUE '',
                        'FIRST_AUTHORISED_DATE' VALUE '',
                        'INTERNATIONAL_BIRTH_DATE' VALUE to_char(lpro.intl_birth_date, 'dd-mm-yyyy'),
                        'MAH_ORG_CODE' VALUE '',
                        'MARKETING_STATUS_ID' VALUE '',
                        'MARKETING_START_DATE' VALUE '',
                        'MARKETING_STOP_DATE' VALUE '',
                        'RISK_OF_SUPPLY_SHORTAGE_F' VALUE '',
                        'RISK_OF_SUPPLY_SHORTAGE_C' VALUE '',
                        'WITHDRAWAL_DATE' VALUE to_char(lic.withdraw_date, 'dd-mm-yyyy'),
                        'SENDER_LOCAL_CODE' VALUE lic.license_id,
                        'COMMENT' VALUE lic.comments,
                        'MASTER_TYPE' VALUE lcty.license_type,
                        'HALO_CODE_SOURCE' VALUE l_halo_code_source,
                        'OWNER_ORG_CODE' VALUE 'ORG35187'
            RETURNING CLOB)
        RETURNING CLOB)
    INTO v_result
    FROM
        lm_license       lic,
        lm_lic_products  llip,
        lm_product       lpro,
        lm_countries     cou,
        lm_license_types lcty
    WHERE
            lic.license_id = llip.license_id
        AND llip.product_id = lpro.product_id
        AND llip.product_id = p_mp_id
        AND lic.country_id = cou.country_id (+)
        AND lic.license_type_id = lcty.license_type_id (+);
                /*AND LCTY.DELETED(+) IS NULL
                AND LLIP.DELETED IS NULL
                AND LIC.DELETED IS NULL*/
                --AND to_char(LIC.last_update_time, 'yyyymmdd') > to_char(current_date-1, 'yyyymmdd');

    RETURN v_result;
EXCEPTION
    WHEN OTHERS THEN
         -- Log Error
        halo_write_log('GET_MP_LICENSES_JSON',
                       'ERROR',
                       'GET_MP_LICENSES_JSON'
                       || 'Unhandled exception: '
                       || sqlerrm
                       || chr(13)
                       || chr(10)
                       || dbms_utility.format_error_backtrace());
         --halo_write_error_log ('GET_MP_LICENSES_JSON '|| 'Unhandled exception: ' || SQLERRM || CHR (13) || CHR (10) || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE());

         -- Make the caller aware
        RAISE;
END GET_MP_LICENSES_JSON;
/


--------------------------------------------------------------
-- GET_MP_MPIDS_JSON
--------------------------------------------------------------


CREATE OR REPLACE EDITIONABLE FUNCTION GET_MP_MPIDS_JSON (
    p_mp_id IN NUMBER
) RETURN CLOB IS

/******************************************************************************************************
--  Purpose              : Fetching product id data from Argus database
--  Input                : N/A (all products are transferred)
--  Changes:             : Created, Praveen Gupta, 19-Jul-2022
   						 : CSL Custom deployment. Updated OWNER_ORG_CODE, PSP, 25-Jun-2026 


******************************************************************************************************/
    v_result           CLOB;
    l_halo_code_source VARCHAR2(100);
BEGIN
    --halo_write_error_log ('GET_MP_MPIDS_JSON ' || 'BEGIN p_MP_ID=' || p_MP_ID);
    halo_write_log('GET_MP_MPIDS_JSON', 'INFO', 'GET_MP_MPIDS_JSON '
                                                || 'BEGIN p_MP_ID='
                                                || p_mp_id);
    SELECT
        halo_char_id
    INTO l_halo_code_source
    FROM
        stg_argus_halo_idmap
    WHERE
        entity_name = 'SOURCES';

    SELECT
        JSON_OBJECT(
            'MPIDs' VALUE nvl(
                JSON_ARRAYAGG(
                    JSON_OBJECT(
                        'MPID' VALUE lpro.product_id,
                        'HALO_CODE_SOURCE' VALUE l_halo_code_source,
                        'SENDER_LOCAL_CODE' VALUE lpro.product_id,
                        'OWNER_ORG_CODE' VALUE 'ORG35187'
                    RETURNING CLOB)
                ),
                '[]'
            )
        FORMAT JSON RETURNING CLOB)
    INTO v_result
    FROM
        lm_product lpro
    WHERE
        lpro.product_id = p_mp_id;

    RETURN v_result;
EXCEPTION
    WHEN OTHERS THEN
            -- Log Error
        halo_write_log('GET_MP_MPIDS_JSON',
                       'ERROR',
                       'GET_MP_MPIDS_JSON'
                       || 'Unhandled exception: '
                       || sqlerrm
                       || chr(13)
                       || chr(10)
                       || dbms_utility.format_error_backtrace());
            --halo_write_error_log ('GET_MP_MPIDS_JSON ' || 'Unhandled exception: ' || SQLERRM || CHR (13) || CHR (10) || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE());

         -- Make the caller aware
        RAISE;
END GET_MP_MPIDS_JSON;
/

--------------------------------------------------------------
-- GET_MP_PP_INGS_JSON
--------------------------------------------------------------
CREATE OR REPLACE EDITIONABLE FUNCTION GET_MP_PP_INGS_JSON (
    p_mp_pp_id IN NUMBER
) RETURN CLOB IS

/******************************************************************************************************
--  Purpose              : Fetching product family data from Argus database
--  Input                : N/A (all products are transferred)
--  Changes:             : Created, Praveen Gupta, 19-Jul-2022
                         : Modified: DD - CHG-168388 - LOW_AMOUNT_NUMER_VALUE, LOW_AMOUNT_NUMER_UNIT make it null
						 : Modified: 21-JUN-2024 - DD - HLP-8646 - LOW_AMOUNT_NUMER_VALUE, LOW_AMOUNT_NUMER_UNIT values were restored
						 : CSL Custom deployment. Updated OWNER_ORG_CODE, PSP, 25-Jun-2026 

******************************************************************************************************/
    v_result CLOB;
BEGIN
    --halo_write_error_log ('GET_MP_PP_INGS_JSON  ' || 'BEGIN p_MP_PP_ID=' || p_MP_PP_ID);
    halo_write_log('GET_MP_PP_INGS_JSON', 'INFO', 'GET_MP_PP_INGS_JSON '
                                                  || 'BEGIN p_MP_PP_ID='
                                                  || p_mp_pp_id);
    SELECT
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'HALO_CODE_SUBSTANCE' VALUE nvl((
                    SELECT
                        halo_char_id
                    FROM
                        stg_argus_halo_idmap
                    WHERE
                            entity_name = 'SUBSTANCES'
                        AND argus_id = lpc.ingredient_id
                ), ''),
                        'INGREDIENT_ROLE' VALUE 'ACT',
                        'LOW_AMOUNT_NUMER_VALUE' VALUE to_char(lpc.concentration),
                        'LOW_AMOUNT_NUMER_PREFIX_CODE' VALUE '',
                        'LOW_AMOUNT_NUMER_UNIT' VALUE ldu.unit, --get description from lm_dose_unit. refer to transfer substance proc
                        'LOW_AMOUNT_DENOM_VALUE' VALUE '',
                        'LOW_AMOUNT_DENOM_PREFIX_CODE' VALUE '',
                        'LOW_AMOUNT_DENOM_UNIT' VALUE '',
                        'HIGH_AMOUNT_NUMER_VALUE' VALUE '',
                        'HIGH_AMOUNT_NUMER_PREFIX_CODE' VALUE '',
                        'HIGH_AMOUNT_NUMER_UNIT' VALUE '',
                        'HIGH_AMOUNT_DENOM_VALUE' VALUE '',
                        'HIGH_AMOUNT_DENOM_PREFIX_CODE' VALUE '',
                        'HIGH_AMOUNT_DENOM_UNIT' VALUE '',
                        'SENDER_LOCAL_CODE' VALUE lpc.ingredient_id,
                        'OWNER_ORG_CODE' VALUE 'ORG35187'

            RETURNING CLOB)
        RETURNING CLOB)
    INTO v_result
    FROM
        lm_product_family         lpf,
        lm_pf_ingredients         lpi,
        lm_product                lp,
        lm_ingredients            li,
        lm_product_concentrations lpc,
        lm_dose_units             ldu
    WHERE
            lpf.family_id = lpi.family_id
        AND lpf.family_id = lp.family_id
        AND lpi.ingredient_id = li.ingredient_id (+)
        AND lp.product_id = lpc.product_id
        AND lpi.ingredient_id = lpc.ingredient_id
        AND lpc.conc_unit_id = ldu.unit_id (+)
        AND lp.product_id = p_mp_pp_id
        AND li.deleted IS NULL
        AND lpf.deleted IS NULL
        AND lpc.deleted IS NULL
        AND lp.deleted IS NULL
        AND lpi.deleted IS NULL
        AND ldu.deleted IS NULL;

    RETURN v_result;
EXCEPTION
    WHEN OTHERS THEN
            -- Log Error
        halo_write_log('GET_MP_PP_INGS_JSON',
                       'ERROR',
                       'GET_MP_PP_INGS_JSON'
                       || 'Unhandled exception: '
                       || sqlerrm
                       || chr(13)
                       || chr(10)
                       || dbms_utility.format_error_backtrace());
            --halo_write_error_log ('GET_MP_PP_INGS_JSON  ' || 'Unhandled exception: ' || SQLERRM || CHR (13) || CHR (10) || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE());

         -- Make the caller aware
        RAISE;
END GET_MP_PP_INGS_JSON;
/

--------------------------------------------------------------
-- GET_MP_PP_JSON
--------------------------------------------------------------
CREATE OR REPLACE EDITIONABLE FUNCTION GET_MP_PP_JSON (
    p_mp_id IN NUMBER
) RETURN CLOB IS

    v_result            CLOB;
    l_source            VARCHAR2(100);
    v__prod_entity_name VARCHAR2(100) := 'PRODUCT';
    v_halo_prod_id      VARCHAR2(200) := NULL;
    /******************************************************************************************************
    --  Purpose              : Fetching formulation data from Argus database
    --  Input                : N/A (all products are transferred)
    --  Changes:             : Created, Praveen Gupta, 19-Jul-2022
							 : CSL Custom deployment. Updated OWNER_ORG_CODE, PSP, 25-Jun-2026 


    ******************************************************************************************************/
BEGIN
        --halo_write_error_log('GET_MP_PP_JSON '|| 'BEGIN p_MP_ID=' || p_MP_ID);
    halo_write_log('GET_MP_PP_JSON', 'INFO', 'GET_MP_PP_JSON '
                                             || 'BEGIN p_MP_ID='
                                             || p_mp_id);
    SELECT
        halo_char_id
    INTO l_source
    FROM
        stg_argus_halo_idmap
    WHERE
        entity_name = 'SOURCES';

    BEGIN
        SELECT
            halo_char_id
        INTO v_halo_prod_id
        FROM
            stg_argus_halo_idmap
        WHERE
                entity_name = v__prod_entity_name
            AND argus_id = p_mp_id;

    EXCEPTION
        WHEN OTHERS THEN
            v_halo_prod_id := NULL;
            halo_write_log(v__prod_entity_name, 'ERROR', 'GET_MP_PP_JSON:  V_HALO_PROD_ID IS NULL FOR ARGUS_ID:' || p_mp_id);
    END;

        -- MPD_MP_IND
    SELECT
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'HALO_CODE' VALUE nvl2(v_halo_prod_id, v_halo_prod_id, ''),
                        'HALO_CODE_PHARM_FORM' VALUE nvl((
                    SELECT
                        halo_char_id
                    FROM
                        stg_argus_halo_idmap
                    WHERE
                            entity_name = 'PHARM_FORMS'
                        AND argus_id = lf.formulation_id
                ), ''),
                        'UNIT_OF_PRESENTATION' VALUE '',
                        'SENDER_LOCAL_CODE' VALUE lpro.product_id,
                        'HALO_CODE_SOURCE' VALUE l_source,
                        'INGREDIENTS' VALUE nvl(
                    get_mp_pp_ings_json(p_mp_pp_id => p_mp_id),
                    '[ ]'
                )
            FORMAT JSON,
                        'OWNER_ORG_CODE' VALUE 'ORG35187' 
						RETURNING CLOB)
        RETURNING CLOB)
    INTO v_result
    FROM
        lm_product     lpro,
        lm_formulation lf
    WHERE
            lpro.product_id = p_mp_id
        AND lpro.formulation_id = lf.formulation_id (+);

    RETURN v_result;
EXCEPTION
    WHEN OTHERS THEN
         -- Log Error
         --halo_write_error_log ('GET_MP_PP_JSON '|| 'Unhandled exception: ' || SQLERRM || CHR (13) || CHR (10) || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE());
        halo_write_log('GET_MP_PP_JSON',
                       'ERROR',
                       'GET_MP_PP_JSON'
                       || 'Unhandled exception: '
                       || sqlerrm
                       || chr(13)
                       || chr(10)
                       || dbms_utility.format_error_backtrace());

         -- Make the caller aware
        RAISE;
END GET_MP_PP_JSON;
/

--------------------------------------------------------------
-- HALO_ICSR_R3_GENERATE_ARGUS_DATA
--------------------------------------------------------------

CREATE OR REPLACE FUNCTION HALO_ICSR_R3_GENERATE_ARGUS_DATA (
    p_case_num VARCHAR2,
    p_state_id VARCHAR2
) RETURN CLOB AS
    /******************************************************************************************************
    --  File Name            : A02_HALO_ICSR_R3_GENERATE_DATA.sql
    --  Purpose              : This will pull the case data from argus db tables in JSON format.
    --  Input                : ARGUS R3 CASE DATA
    --  Created by           : Shobha Kashyap 22-MAY-2020 - V1
    11-Jun-2020 SHK, Added LISTEDNESS logic,
    G_K_4_R_4_NF,G_K_4_R_5_NF logic has been added
    11-Jun-2020 Kranthi, updated C_1_6_1_CLAS logic commented joins
    Exception blocks added in each subsection section C,D,E,F,G,H
    START_DATETIME_NF,STOP_DATETIME_NF,LOT_NO_NF updated and added ND CDR.SEQ_NUM=CNF.SEQ_NUM in sub query to avoid mutiple rows.
    Peter Stroyer Pallesen 23-Jun-2020 v3
    - Added State_ID as a call parameter
    - Updated case tables to use v$ views instead of raw tables to ensure that deleted rows are never retrieved
    - Added left join on narrative select to ensure that values are retrieves in all scenarios
    -----------------------------
    -- V2: PSP: 19. Sep 2020:
    -----------------------------
    updated all json_object to return varchar2 32000 (default is 4000 which is not sufficient in all case     scenarios)
    -----------------------------
    -- V3: PSP: 4-OCT-2020 Updated onset- and stop date to respect partial dates
    -----------------------------
    -----------------------------
    -- V4: PSP: 30-DEC-2020 Updated join for G_K_3_3_MANU_NAM (bug fix). (CSSERVICE-134520)
    --                      Added Event intensity - E_I_INTENSITY
    --                      Updated logic for g_k_2_5_drug_code
    --
    -- V5: PSP: 07-03-2021 Updated to send both determined and reported causality (CSSERVICE-135518)
    -- V6: PSP: 30-05-2021: Updated logic for g_k_2_2 to ensure names are also transferred for non-coded products (conc. med). Single-subq. error on product table resolved. CSSERVICE-137311
    -- V7: PSP, 04-08-2021: JIRA HAL-9, Added support for Sender comment (H.4)
    -- V8: PSP, 14-10-2021: JIRA HAL-163 Updated PRODUCT_ID to send pat_exposure for study products
    --                      JIRA HAL-166 added PAT_STAT_PREG, ONSET_LATENCY, E_I_2_1B_HLT_CODE
    -- V9: PSP, 02-12-2021: added D_7_1_R_1B_HLT_CODE, D_7_1_R_1B_HLGT_CODE, D_7_1_R_1B_PT_CODE, E_I_2_1B_PT_CODE, E_I_2_1B_HLGT_CODE  JIRA HAL-166
    -- V10: PK, 18-09-2022: Ongoing - updating to align with new HALO R3 ingestion API..
    -- V11: PSP, 18-09-2022: Added R3 decoding to Patient age units, Updated reporter email tag (REPORTEREMAILADDRESS)
    --                       General update to handle CLOB data (using DBMS_LOB package to concatenate instead of ||
    --                       Updated causality result logic to transfer text value (HALO supports both EU and text values)
    -- V12: PSP, 02-10-2022: Updated logic of causality source and method to send text instead of internal IDs
    -- V13: PSP, 05-10-2022: Updated listedness logic to send correct values (HALO uses the same code list values)
    -- V14: PSP 26-06-2022: Added listedness for multiple datasheets / licenses. Added Transfer of case refs. JIRA HLP-1349
    -- V15: PSP 08-10-2022: Added SORT_ORDER on events and products (Backported from JIRA HLP-1349 and 1056)
    -- V16: PK, 06-01-2022: https://insife.atlassian.net/browse/HLP-3127, Mapping updates to comply with new HALO 4 integration (merged by PSP)
    -- V17: PSP, 06-01-2023: https://insife.atlassian.net/browse/HLP-2643:
				Updated to handle attachments as json elements instead of concatenated strings ('||')
				Added file details for literature ref. section
				Changed H_3 to use dbms_lob.append instead of "||" to concatenate
				C_1_6_1 updated to send true/false
				C_1_7 updated to use R3 values
    --V18: DD, 31-01-2023: updated D_7_1_R_2, D_7_1_R_4, D_8_R_4, D_8_R_5 to remover single row query error
    -- V19: ED, 23-02-2023: fixed all incomplete date formats as YYYY, YYYYMM, YYYYMMDD
    -- V20: ED, 08-03-2023: fixed D_9_3 ::: autopsy (DECODE)
                            C_1_6_1 (logic to set false when no attachments, true otherwise)
                            LITERATURE_INFO_C_4_R join on case_literature/notes_attach
                            D_7_3::: VALUE DECODE(cpat.concom_therapy), D_7_1/D_8_r ::: fix joins on Parent/Patient Med/Drug history.
                            C_1_8_1 codes to 1 (Authority) when E2B Auth# present, null otherwise
                            C_1_9_1 decoded when there is E2B Report duplicate, C_1_9_1_R with content
                            C_1_11_1 mapped to 1 Nullification, 2 Amendment
                            G_K_2_2 mapped product name from either drug dictionary (if suspect, company product) or entered product name otherwise
                            PRODUCT_TYPE decoded based on Drug/Vaccine/Device view
    -- V21: ED, 09-03-2023  Fixed spelling AUTOPSY_INFO_D_9_4_R, INGR_G_K_2_3_R, linked reports under grouping LINKED_REP_INFO_C_1_10
                            Grouping PAT_HIST_D_7_1, PAT_PAST_DRUG_D_8_R
                            Drug Dosing PRODUCT_DOSE_G_K_4 / G_K_4*
                            Event MedDRA version E_I_2_1A
    -- V22: ED, 16-03-2023  D_2_2_1B and G_K_6B: UCUM decode gest period unit, D_10_2_2B UCUM parent age unit
                            G_K_4_R_2, G_K_4_R_3: interval_dosage unit and UCUM def
    -- V23: ED, 16-May-2023  D_10_7_1_R_1A, D_10_8_R_6A, D_10_8_R_7A, D_9_4_R_1A, D_9_2_R_1A, D_7_1_R_1A, D_8_R_6A, D_8_R_7A, E_I_2_1A, H_3_R_1A, F_R_2_2A (MedDRA version) applied substr(version_number,1,4)
    -- V24: ED, 26-May-2023 Re-added HLP-3564 (lost in previous merge) - Listedness error
                            E_I_7 Event outcome from R3 Flex recateg codelist
                            C_1_9_1_R_1 : reference types from HALO_CONFIG table to make it generic (PARAMETER = 'ARGUS_ICSR_R3_EXPORT_REF_TYPE'
                            G_K_4_R_10_1 : Route of administration - changed to EDQM_ID
                            G_K_4_R_9_1 : Formulation - changed to EDQM_ID
                            G_K_8 : Map E2B R3 decodes
    -- V25: ED, 07-Jun-2023 G_K_4_R_10_1 : route of admin text, G_K_4_R_10_2B: route of admin EDQM
                            G_K_4_R_9_1 : formulation text, G_K_4_R_9_2B : formulation EDQM
                            FREQUENCY_B_4_K_5_3 :  added Frequency plain text
    -- V26: ED, 28-Jun-2023 G_K_2_5 - updated to map true/false instead of O/1
    -- V27: ED, 29-Jun-2023 section E-(events), on tob of E_I_2_1B, adding E_I_2_1B_PT_CODE, E_I_2_1B_HLT_CODE, E_I_2_1B_HLGT_CODE, E_I_2_1B_SOC_CODE
	 -- V28: DD, 24-July-2023 commented duplicate JSON elements: C_1_11_1, C_1_11_2
    -- V29: ED, 30-Aug-2023 D_10_3 raised a too many rows when parent information is present, G_K_4_R_9_2B updated to get one record from EDQM decode
    -- V30: ED, 13-Sep-2023 Added custom section KEYWORDS - Case classifications and references
	-- V31: PSP, 01-10-2023 HLP-6280: Updated pregnancy keyword logic (renamed from Argus specific pat_stat_preg to PREGNANT, and added mapping logic on the argus side rather than in HALO)
	-- V32: PSP, 01-10-2023 HLP-6330, 6492: Added all meddra levels for patient- and parent past med. hist blocks, Added SUSAR keyword
	-- V33: PSP, 24-10-2023, HLP-6739: Bug fixed medical confirm (convert to r3 values)
	-- V34: PSP, 27-10-2023, Minor correction to the logic of 'ARGUS_ICSR_R3_EXPORT_REF_TYPE' - changed to be EXCLUSION list.
	-- V35: PSP, 02-11-2023, Minor update to medically confirmed (E.I.8) logic: Null if blank in Argus (previously defaulting to false)
	-- V36: JD, 24-10-2023, Bug fixed C_1_8_1 (ORA-01427 error when ref_type_id 15 and 16 exist)
 -- V37: DD, 31-10-2023 , Fixed death date format to comply to R3 values
 -- V38: PSP, 07-11-2023, HLP-6976: Corrected Datasheet listednesss section (Sequence numbers + decoding of listedness values), added E_I_ONSET_LATENCY
	-- V39: PSP, 07-11-2023, HLP-7002 - Added all meddra levels to Death causes (d.9.2.r and d.9.4.r)
		-- V40: PSP, 14-11-2023, HLP-7103 - Updated calculation of g.k.1 to send standard R3 (including interacting / drug not admin.) - the existing JSON tags for Interacting / Drug not admin. are not supported by HALO. + added DRUG_NAME_OVERRIDE
-- V41 DD, 16-11-2023, Added function get_c11 to generate valid c_1_1 value
-- V42 DD, 05-Dec-2023- Added function  get_lm_value to get codelist values via dynamic sql
-- V43 PK, 16-Jan-2024 - Updated code to include Device fields and fixed issues found during Unit Testing - (Parent DOB, Parent Date of LMP, Parent Initials, G_K_5b)
-- V44 PK, 28-Feb-2024 - Updated G_K_3_1, G_K_3_2, G_K_3_3, G_K_2_4 and G_K_2_5 to remove LISTAGG function
-- V45 PK, 20-Mar-2024 - Updated G_K_2_3_R_3B to send UCUM code instead of conc_unit_id
-- V46 PK, 05-Apr-2024 - Updated for following elements - Updated:FREQUENCY_B_4_K_5_3, Added Elements - G_K_2_1_1A, D_10_7_2, G_k_2_1_2a, G_k_2_1_2b, G_K_11, G_k_2_3_r_2a, G_k_2_3_r_2b
-- V47 PK, 20-Dec-2024 - Updated for API 3.0 (CHG-182066)
-- V48 AG, 21-FEB-2025 - updated DEATH_INFO_D_9_2_R section: as their is extra join for case_event table, updated AUTOPSY_INFO_D_9_4_R section: as their is extra join for case_event table,
                        updated DEVICE_INFO_B_4_K_FDA section: their is a missing join on seq_num of case_product and case_prod_devices table and on table join is missing lm_lic_products
--V49 AG, 22-APR-2025   - updated the function to exclude the attachment if it was previously trasffered.
-- V50 PSP, 30-JUN-2026 - Removed usage of Argus 8.2.3+ views (v$lm_formulation_edqm, G_K_4_R_9_2B) and use of ESM_MAPPING_UTL.F_GET_MEDICINALPRODUCT (G_K_2_2)
-- V51 SB, 22-JUL-2026 - Change C_1_1 from nvl to case when


-----------------------------
    ******************************************************************************************************/
    l_case_id             NUMBER;
    l_json_request        CLOB;
    l_temp_str            CLOB;
    l_case_num            VARCHAR2(20);
    PRAGMA autonomous_transaction;
    v_send_attachment     NUMBER;
    l_transfer_attachment NUMBER;
BEGIN
    dbms_lob.createtemporary(l_json_request, FALSE);
    dbms_lob.createtemporary(l_temp_str, FALSE);
    SELECT
        case_id
    INTO l_case_id
    FROM
        case_master
    WHERE
        case_num = p_case_num;

    SELECT
        value
    INTO v_send_attachment
    FROM
        halo_config
    WHERE
        parameter = 'SEND_ATTACHMENT';
    /*************************************************C-section**********************************************/
    BEGIN
        SELECT
            JSON_OBJECT(
                'CASE_ID' VALUE cm.case_id,
                        'CASE_NUM' VALUE cm.case_num,
                        'VERSION_NO' VALUE 0,
                        'WF_ACTIVITY_ID' VALUE(
                    SELECT
                        decode(state_id, 1, '1', state_name)
                    FROM
                        cfg_workflow_states
                    WHERE
                        state_id = p_state_id
                ),
                        'C_1_1' VALUE CASE
                                    WHEN cm.e2b_ww_number IS NOT NULL THEN
                                        cm.e2b_ww_number
                                    ELSE
                                        get_c11(cm.case_id)
                                END,
                        'C_1_2' VALUE to_char(cm.create_time, 'YYYY-MM-DD HH24:MI:SS'),
                        'C_1_3' VALUE(
                    SELECT
                        e2b_code
                    FROM
                        lm_report_type lrt
                    WHERE
                        cm.rpt_type_id = lrt.rpt_type_id
                ), --cm.rpt_type_id,
                        'C_1_4' VALUE to_char(cm.init_rept_date, 'YYYYMMDD'),
                        'C_1_5' VALUE to_char(
                    nvl(cm.followup_date, cm.init_rept_date),
                    'YYYYMMDD'
                ),
                        'C_1_6_1' VALUE(
                    CASE(
                        SELECT
                            COUNT(*)
                        FROM
                            case_notes_attach cna
                        WHERE
                                cna.case_id = cm.case_id
                            AND cna.deleted IS NULL
                    )
                        WHEN 0 THEN
                            'false'
                        ELSE
                            'true'
                    END
                ),
                        'C_1_7' VALUE(
                    CASE ca.seriousness
                        WHEN 1 THEN
                            'true'
                        ELSE
                            'false'
                    END
                ),
                        'C_1_8_1' VALUE(
                    SELECT DISTINCT
                        decode(ref_type_id, 15, ref_no, 16, ref_no,
                               NULL, cm.case_num)
                    FROM
                        case_reference
                    WHERE
                            case_id = cm.case_id
                        AND ref_type_id IN(15, 16)
                        AND deleted IS NULL
                        AND ROWNUM = 1
                ),
                        'C_1_8_2' VALUE(
                    CASE
                        WHEN EXISTS(
                            SELECT
                                1
                            FROM
                                case_reference
                            WHERE
                                    case_id = cm.case_id
                                AND ref_type_id = 15
                                AND deleted IS NULL
                        ) THEN
                            1
                        ELSE
                            NULL
                    END
                ),
                        'C_1_9_1' VALUE(
                    CASE
                        WHEN EXISTS(
                            SELECT
                                1
                            FROM
                                case_reference
                            WHERE
                                    case_id = cm.case_id
                                AND ref_type_id = 12
                                AND deleted IS NULL
                        ) THEN
                            'true'
                    END
                ),
                        'C_1_11_1' VALUE(
                    SELECT
                        2
                    FROM
                        (
                            SELECT
                                nvl(amendment, NULL) amendment
                            FROM
                                case_followup cf
                            WHERE
                                    amendment = 1
                                AND cm.case_id = cf.case_id
                                AND cf.deleted IS NULL
                            ORDER BY
                                time_stamp DESC
                        )
                    WHERE
                        ROWNUM = 1
                ),
			       /*     'C_1_11_1' VALUE(
					SELECT
						state_id
					FROM
						case_master cm1
					WHERE
						 cm1.case_id = cm.case_id
						AND state_id = 1
						AND cm1.deleted IS NULL
				), */
                        'C_1_11_2' VALUE(
                    SELECT
                        justification
                    FROM
                        (
                            SELECT
                                justification
                            FROM
                                case_followup cf
                            WHERE
                                    amendment = 1
                                AND cm.case_id = cf.case_id
                                AND cf.deleted IS NULL
                            ORDER BY
                                time_stamp DESC
                        )
                    WHERE
                        ROWNUM = 1
                ),
			         /*   'C_1_11_2' VALUE(
					SELECT
						j_text
					FROM
						(
							SELECT
								j_text
							FROM
								case_justifications cj
							WHERE
								 cj.case_id = cm.case_id
								AND field_id = 2110018
								AND cj.deleted IS NULL
							ORDER BY
								updated_time DESC
						)
					WHERE
						ROWNUM = 1
				), */
                        'C_5_2' VALUE cs.study_desc,
                        'C_5_3' VALUE cs.study_num,
                        'C_5_4' VALUE cs.classification_id,
                        'CENTRAL_RECEIPT_DATE' VALUE to_char(cm.safety_date, 'YYYYMMDD'),
                        'INVALID_CASE' VALUE cm.deleted
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master   cm
            LEFT JOIN case_assess   ca ON cm.case_id = ca.case_id
            LEFT JOIN case_followup cf ON cm.case_id = cf.case_id
                                          AND ( cf.seq_num IS NULL
                                                OR cf.seq_num = (
                SELECT
                    nvl(
                        max(seq_num),
                        NULL
                    )
                FROM
                    case_followup
                WHERE
                        significant = 1
                    AND case_id = l_case_id
            ) )
            LEFT JOIN case_study    cs ON cm.case_id = cs.case_id
        WHERE



        /*
            case_master   cm,
            case_assess   ca,
            case_followup cf,
            case_study    cs
        WHERE
                cm.case_id = ca.case_id
            AND cm.case_id = cs.case_id (+)
            AND cm.case_id = cf.case_id (+)
            AND ( cf.seq_num IS NULL
                  OR cf.seq_num = (
                SELECT
                    nvl(MAX(seq_num),
                        NULL)
                FROM
                    case_followup
                WHERE
                        significant = 1
                    AND case_id = l_case_id
            ) ) */


            cf.deleted IS NULL
            AND cs.deleted IS NULL
            AND cm.deleted IS NULL
            AND ca.deleted IS NULL
            AND cm.case_id = l_case_id;

        dbms_lob.append(l_json_request,
                        to_clob(rtrim(l_temp_str, '}')));

      ------------------------------------------------------------------
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                    'SEQ_NUM' VALUE cr.seq_num,
                    'C_1_9_1_R_1' VALUE(
                        SELECT
                            type_desc
                        FROM
                            lm_ref_types
                        WHERE
                            cr.ref_type_id = ref_type_id
                    ),
                    'C_1_9_1_R_2' VALUE cr.ref_no
                RETURNING CLOB)
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master    cm,
            case_reference cr
        WHERE
                cm.case_id = cr.case_id
            AND cr.deleted IS NULL
            AND cr.ref_type_id IN (
                SELECT
                    ref_type_id
                FROM
                    lm_ref_types
                WHERE
                    type_desc NOT IN (
                        SELECT
                            value
                        FROM
                            halo_config
                        WHERE
                            parameter = 'ARGUS_ICSR_R3_EXPORT_REF_TYPE'
                    )
            )
            AND cm.case_id = l_case_id;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"CASE_REF_C_1_9":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;
      ------------------------------------------------------------------
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                    'C_1_10_R' VALUE cr.ref_no
                RETURNING CLOB)
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master    cm,
            case_reference cr
        WHERE
                cm.case_id = cr.case_id
            AND cr.deleted IS NULL
            AND cm.case_id = l_case_id;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"LINKED_REP_INFO_C_1_10":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;
      ------------------------------------------------------------------
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cr.case_id,
                            'SEQ_NUM' VALUE cr.seq_num,
                            'C_2_R_1_1' VALUE nvl(cr.prefix, crnf.prefix_nf),
                            'C_2_R_1_2' VALUE nvl(cr.first_name, crnf.first_name_nf),
                            'C_2_R_1_3' VALUE nvl(cr.middle_name, crnf.middle_name_nf),
                            'C_2_R_1_4' VALUE nvl(cr.last_name, crnf.last_name_nf),
                            'C_2_R_2_1' VALUE nvl(cr.institution, crnf.institution_nf),
                            'C_2_R_2_2' VALUE nvl(cr.department, crnf.department_nf),
                            'C_2_R_2_3' VALUE nvl(cr.address, crnf.address_nf)
                                              || nvl(cr.address_2, crnf.address_2_nf),
                            'C_2_R_2_4' VALUE nvl(cr.city, crnf.city_nf),
                            'C_2_R_2_5' VALUE nvl(cr.state, crnf.state_nf),
                            'C_2_R_2_6' VALUE nvl(cr.postcode, crnf.postcode_nf),
                            'C_2_R_2_7' VALUE nvl(cr.phone, crnf.phone_nf),
                            'C_2_R_3' VALUE(
                        SELECT DISTINCT
                            lc.a2
                        FROM
                            lm_countries lc
                        WHERE
                                lc.country_id = cr.country_id
                            AND lc.deleted IS NULL
--                                      AND ROWNUM < 2
                    ),
                            'C_2_R_4' VALUE lrt.e2b_code,
                            'C_2_R_5' VALUE cr.primary_contact,
                            'REPORTEREMAILADDRESS' VALUE cr.email
                RETURNING CLOB)
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master       cm
            LEFT OUTER JOIN case_reporters    cr ON cr.case_id = cm.case_id
            LEFT OUTER JOIN lm_reporter_type  lrt ON cr.reporter_type = lrt.rptr_type_id
            LEFT OUTER JOIN case_reporters_nf crnf ON crnf.case_id = cm.case_id
                                                      AND crnf.seq_num = cr.seq_num
        WHERE
                cm.case_id = l_case_id
            AND cr.deleted IS NULL;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"REPORTER_INFO_C_2_R":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                            'C_4_R_1' VALUE(' JOURNAL: '
                                            || nvl(cl.journal, 'NA')
                                            || ' AUTHOR: '
                                            || nvl(cl.author, 'NA')
                                            || ' TITLE: '
                                            || nvl(cl.title, 'NA')
                                            || ' VOLUME: '
                                            || nvl(cl.vol, 'NA')
                                            || ' YEAR: '
                                            || nvl(cl.year, 'NA')
                                            || ' PGS: '
                                            || nvl(cl.pgs, 'NA')),
                            'C_4_R_2_FILE_NAME' VALUE cna.notes,
                            'C_4_R_2' VALUE apex_web_service.blob2clobbase64(cna.data),
                            'C_4_R_2_MEDIA_TYPE' VALUE substr(cna.filetype, -4)
                RETURNING CLOB)
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master       cm
            LEFT OUTER JOIN case_literature   cl ON cl.case_id = cm.case_id
            LEFT OUTER JOIN case_notes_attach cna ON cna.case_id = cl.case_id
                                                     AND cna.literature_seq_num = cl.seq_num
        WHERE
                cm.case_id = l_case_id
            AND ( cl.journal IS NOT NULL
                  OR cl.author IS NOT NULL
                  OR cl.title IS NOT NULL
                  OR cl.vol IS NOT NULL
                  OR cl.year IS NOT NULL
                  OR cl.pgs IS NOT NULL )
            AND cm.deleted IS NULL;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"LITERATURE_INFO_C_4_R":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;
      --------------------------
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                            'C_5_1_R_1' VALUE substr(
                        to_char(lsr.reference),
                        0,
                        1999
                    ),
                            'C_5_1_R_2' VALUE(
                        SELECT DISTINCT
                            a2
                        FROM
                            lm_countries lc
                        WHERE
                                lc.country_id = lsr.country_id
                            AND lc.deleted IS NULL
                            AND ROWNUM < 2
                    )
                RETURNING CLOB)
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master         cm,
            case_study          cs,
            lm_study_references lsr
        WHERE
                cs.case_id = cm.case_id
            AND cs.study_key = lsr.study_key
            AND cs.deleted IS NULL
            AND cm.deleted IS NULL
            AND cm.case_id = l_case_id;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"STUDY_INFO_C_5_1_R":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || ' C-section - While generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;

    IF v_send_attachment = 1 THEN
        BEGIN
            SELECT
                COUNT(1)
            INTO l_transfer_attachment
            FROM
                halo_transfer_attachment hta,
                case_master              cm
            WHERE
                    hta.case_id = cm.case_id
                AND hta.status = 0;

            IF l_transfer_attachment = 0 THEN
                SELECT
                    JSON_ARRAYAGG(
                        JSON_OBJECT(
                            'CASE_ID' VALUE cm.case_id,
                                    'C_1_6_1_R_1' VALUE cna.keywords,
                                    'C_1_6_1_R_2' VALUE apex_web_service.blob2clobbase64(cna.data),
                                    'C_1_6_1_R_2_FILE_NAME' VALUE cna.filetype,
                                    'C_1_6_1_R_2_MEDIA_TYPE' VALUE substr(cna.filetype, -4),
                                    'C_1_6_1_R_2_DOC_TYPE' VALUE lc.classification
                        RETURNING CLOB)
                    RETURNING CLOB)
                INTO l_temp_str
                FROM
                    case_notes_attach cna,
                    case_master       cm,
                    lm_classification lc
                WHERE
                        cm.case_id = cna.case_id (+)
                    AND cna.classification = lc.classification_id (+)
                    AND cm.case_num = p_case_num
                    AND cm.deleted IS NULL
                    AND cna.deleted IS NULL
                    AND lc.classification NOT IN (
                        SELECT
                            value
                        FROM
                            halo_config
                        WHERE
                            parameter = 'EXCLUDE_ATTACHMENT_TYPE'
                    );

                IF l_temp_str IS NOT NULL THEN
                    dbms_lob.append(l_json_request,
                                    to_clob(',"ADDITIONAL_DOCS_C_1_6_1_R":'));
                    dbms_lob.append(l_json_request,
                                    to_clob(l_temp_str));
                END IF;

--        UPDATE HALO_TRANSFER_ATTACHMENT
--        SET STATUS = 1
--        WHERE CASE_ID = (SELECT CASE_ID FROM CASE_MASTER WHERE CASE_NUM = p_case_num);

            ELSE
                SELECT
                    JSON_ARRAYAGG(
                        JSON_OBJECT(
                            'CASE_ID' VALUE cm.case_id,
                                    'C_1_6_1_R_1' VALUE cna.keywords,
                                    'C_1_6_1_R_2' VALUE apex_web_service.blob2clobbase64(cna.data),
                                    'C_1_6_1_R_2_FILE_NAME' VALUE cna.filetype,
                                    'C_1_6_1_R_2_MEDIA_TYPE' VALUE substr(cna.filetype, -4),
                                    'C_1_6_1_R_2_DOC_TYPE' VALUE lc.classification
                        RETURNING CLOB)
                    RETURNING CLOB)
                INTO l_temp_str
                FROM
                    case_notes_attach        cna,
                    case_master              cm,
                    lm_classification        lc,
                    halo_transfer_attachment hta
                WHERE
                        cm.case_id = cna.case_id (+)
                    AND cna.classification = lc.classification_id (+)
                    AND cna.case_id = hta.case_id
                    AND cna.seq_num = hta.seq_num
                    AND cm.case_num = p_case_num
                    AND hta.status = 0
                    AND cm.deleted IS NULL
                    AND cna.deleted IS NULL
                    AND lc.classification NOT IN (
                        SELECT
                            value
                        FROM
                            halo_config
                        WHERE
                            parameter = 'EXCLUDE_ATTACHMENT_TYPE'
                    );

                IF l_temp_str IS NOT NULL THEN
                    dbms_lob.append(l_json_request,
                                    to_clob(',"ADDITIONAL_DOCS_C_1_6_1_R":'));
                    dbms_lob.append(l_json_request,
                                    to_clob(l_temp_str));
                END IF;

--        UPDATE HALO_TRANSFER_ATTACHMENT
--        SET STATUS = 1
--        WHERE CASE_ID = (SELECT CASE_ID FROM CASE_MASTER WHERE CASE_NUM = p_case_num)
--        AND STATUS = 0;

            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARISG_DATA: '
                         || ' C-section - ADDITIONAL_DOCS_C_1_6_1_R - While generating JSON data for case: '
                         || p_case_num
                         || '  '
                         || substr(sqlerrm, 1, 1000) );
        END;

        COMMIT;
    END IF;
    /*************************************************D-section**********************************************/
    BEGIN
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                            'D_2_1' VALUE nvl(
                        decode(cpat.pat_dob_res,
                               8,
                               to_char(cpat.pat_dob, 'YYYYMMDD'),
                               7,
                               to_char(cpat.pat_dob, 'YYYYMM'),
                               5,
                               to_char(cpat.pat_dob, 'YYYY')),
                        NULL
                    ),
                            --'D_2_1' VALUE (SELECT nvl(pat_dob_nf, NULL) FROM case_pat_info_nf WHERE case_id = cm.case_id),

                            'D_2_2A' VALUE cpat.pat_age,
                            'D_2_2B' VALUE(
                        SELECT
                            display_value
                        FROM
                            code_list_detail_discrete
                        WHERE
                                code_list_id = 'AGE_UNITS'
                            AND decode_context = 'UCUM_CODE'
                            AND code = cpat.age_unit_id
                    ),
                            'D_2_2_1A' VALUE nvl(cpreg.gest_period, NULL),
                            'D_2_2_1B' VALUE(
                        SELECT
                            display_value
                        FROM
                            code_list_detail_discrete
                        WHERE
                                code_list_id = 'AGE_UNITS'
                            AND decode_context = 'UCUM_CODE'
                            AND code = cpreg.gest_period_unit
                    ),
                            'D_2_3' VALUE(
                        SELECT
                            e2b_code
                        FROM
                            lm_age_groups
                        WHERE
                            age_group_id = cpat.age_group_id
                    ), --cpat.age_group_id,
                            'D_3' VALUE cpat.pat_weight_kg,
                            'D_4' VALUE cpat.pat_height_cm,
                            'D_5' VALUE(
                        SELECT
                            e2b_code
                        FROM
                            lm_gender
                        WHERE
                                cpat.gender_id = gender_id(+)
                            AND deleted IS NULL
                    ),
                            'D_7_3' VALUE decode(cpat.concom_therapy, 1, 'true', NULL),
                            'D_9_1' VALUE
                        CASE
                            WHEN cdn.death_date_nf IS NOT NULL
                                 AND cdn.death_date_nf IN('ASKU', 'NASK') THEN
                                esm_mapping_utl.f_get_null_flavor(cdn.death_date_nf)
                            WHEN cd.death_date_res IN(5, 7, 8) THEN
                                decode(cd.death_date_res,
                                       5,
                                       to_char(cd.death_date, 'YYYY'),
                                       7,
                                       to_char(cd.death_date, 'YYYYMM'),
                                       8,
                                       to_char(cd.death_date, 'YYYYMMDD'),
                                       NULL)
                            ELSE
                                NULL
                        END,
                            'DEATH_DATE_RES' VALUE nvl(cd.death_date_res, NULL),
/*
				            'D_9_1' VALUE nvl((
						SELECT
							death_date_nf
						FROM
							case_death_nf
						WHERE
							case_id = cm.case_id
					), NULL),
*/
                            'D_9_3' VALUE decode(cd.autopsy, 8, 'true', 9, 'true',
                                                 10, 'true', 4, 'false', 12,
                                                 'UNK', NULL),
                            'D_1' VALUE(
                        SELECT
                            nvl(pat_initials,
                                nvl(pat_initials_nf, NULL))
                        FROM
                            case_pat_info_nf,
                            case_pat_info
                        WHERE
                                case_pat_info.case_id = case_pat_info_nf.case_id(+)
                            AND case_pat_info.case_id = cm.case_id
                            AND case_pat_info.deleted IS NULL
                    ),
                            'D_1_1_1' VALUE nvl((
                        SELECT
                            LISTAGG(ref_no, ', ') WITHIN GROUP(
                            ORDER BY
                                1
                            )
                        FROM
                            case_reference
                        WHERE
                                case_id = cm.case_id
                            AND ref_type_id = 13
                            AND case_reference.deleted IS NULL
                        GROUP BY
                            case_id
                    ),
                                                NULL),
                            'D_1_1_2' VALUE nvl((
                        SELECT
                            LISTAGG(ref_no, ', ') WITHIN GROUP(
                            ORDER BY
                                1
                            )
                        FROM
                            case_reference
                        WHERE
                                case_id = cm.case_id
                            AND ref_type_id = 14
                            AND case_reference.deleted IS NULL
                        GROUP BY
                            case_id
                    ),
                                                NULL),
                            'D_1_1_3' VALUE nvl((
                        SELECT
                            LISTAGG(ref_no, ', ') WITHIN GROUP(
                            ORDER BY
                                1
                            )
                        FROM
                            case_reference
                        WHERE
                                case_id = cm.case_id
                            AND ref_type_id = 5
                            AND case_reference.deleted IS NULL
                        GROUP BY
                            case_id
                    ),
                                                NULL),
                            'D_6' VALUE decode(
                        nvl(cpreg.date_of_lmp_res, 0),
                        0,
                        cpreg.date_of_lmp_partial,
                        8,
                        to_char(cpreg.date_of_lmp, 'YYYY-MM-DD'),
                        5,
                        to_char(cpreg.date_of_lmp, 'YYYY'),
                        7,
                        to_char(cpreg.date_of_lmp, 'YYYY-MM')
                    ),
                            'D_1_1_4' VALUE cpat.pat_subj_num,
                            'D_10_1' VALUE(nvl(cpi.initials, NULL)),
                            'D_10_2_1' VALUE(nvl(
                        decode(
                            nvl(cpi.dob_res, 0),
                            0,
                            cpi.dob_partial,
                            8,
                            to_char(cpi.dob, 'YYYYMMDD'),
                            5,
                            to_char(cpi.dob, 'YYYY'),
                            7,
                            to_char(cpi.dob, 'YYYYMM')
                        ),
                        NULL
                    )),
                            'D_10_2_2A' VALUE cpi.age,
                            'D_10_2_2B' VALUE(
                        SELECT
                            decode(display_value, '{Decade}', 'de', '10.a', 'de',
                                   display_value)
                        FROM
                            code_list_detail_discrete
                        WHERE
                                code_list_id = 'AGE_UNITS'
                            AND decode_context = 'UCUM_CODE'
                            AND code = cpi.age_unit_id
                    ),
                            'D_10_3' VALUE(nvl(
                        decode(
                            nvl(cpi.date_of_lmp_res, 0),
                            0,
                            cpi.date_of_lmp_partial,
                            8,
                            to_char(cpi.date_of_lmp, 'YYYY-MM-DD'),
                            5,
                            to_char(cpi.date_of_lmp, 'YYYY'),
                            7,
                            to_char(cpi.date_of_lmp, 'YYYY-MM')
                        ),
                        NULL
                    )),
                            'D_10_4' VALUE cpi.weight_kg,
                            'D_10_5' VALUE cpi.height_cm,
                            'D_10_6' VALUE(
                        SELECT
                            e2b_code
                        FROM
                            lm_gender
                        WHERE
                                cpi.gender_id = gender_id(+)
                            AND deleted IS NULL
                    ),
                            'D_10_7_2' VALUE(esm_utl.f_parent_notes(l_case_id, 10000, 0, NULL, NULL)),
                            'PREGNANT' VALUE
                        CASE cpat.pat_stat_preg
                            WHEN 0 THEN
                                'No'
                            WHEN 1 THEN
                                'Yes'
                            WHEN 2 THEN
                                'Unknown'
                            WHEN 3 THEN
                                'N/A'
                            ELSE
                                NULL
                        END
                RETURNING CLOB)
            )
        INTO l_temp_str
        FROM
            case_pat_info    cpat, case_master      cm
            LEFT OUTER JOIN case_parent_info cpi ON cpi.case_id = cm.case_id
            LEFT OUTER JOIN case_pregnancy   cpreg ON cpreg.case_id = cm.case_id
                                                    AND cpreg.parent = '0'
            LEFT OUTER JOIN case_death       cd ON cd.case_id = cm.case_id
            LEFT OUTER JOIN case_death_nf    cdn ON cdn.case_id = cm.case_id
        WHERE
                cm.case_id = l_case_id
            AND cpat.case_id = cm.case_id
            AND cpat.deleted IS NULL
            AND cm.deleted IS NULL;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"PATIENT_D":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || ' PATIENT_D-section - While generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;

    BEGIN
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cph.case_id,
                            'SEQ_NUM' VALUE cph.seq_num,
                            'D_10_7_1_R_1A' VALUE(
                        SELECT
                            substr(version_number, 1, 4)
                        FROM
                            cfg_dictionaries
                        WHERE
                                dict_id = cph.item_dict
                            AND cfg_dictionaries.deleted IS NULL
                    ),
                            'D_10_7_1_R_1B' VALUE cph.item_llt_code,
                            'D_10_7_1_R_6' VALUE cph.family_history,
                            'D_10_7_1_R_1B_HLT_CODE' VALUE cph.item_hlt_code,
                            'D_10_7_1_R_1B_HLGT_CODE' VALUE cph.item_hlgt_code,
                            'D_10_7_1_R_1B_PT_CODE' VALUE cph.item_code,
                            'D_10_7_1_R_1B_SOC_CODE' VALUE cph.item_soc_code,
                            'D_10_7_1_R_2' VALUE(
                        SELECT
                            nvl(
                                decode(start_date_res,
                                       0,
                                       nvl(start_date_nf, NULL),
                                       8,
                                       to_char(start_date, 'YYYYMMDD'),
                                       5,
                                       to_char(start_date, 'YYYY'),
                                       7,
                                       to_char(start_date, 'YYYYMM')),
                                NULL
                            )
                        FROM
                            case_pat_hist,
                            case_pat_hist_nf
                        WHERE
                                case_pat_hist.case_id = case_pat_hist_nf.case_id(+)
                            AND case_pat_hist.seq_num = case_pat_hist_nf.seq_num(+)
                            AND case_pat_hist.case_id = cph.case_id
                            AND case_pat_hist.seq_num = cph.seq_num
                            AND case_pat_hist.deleted IS NULL
                    ),
                            'D_10_7_1_R_3' VALUE decode(cph.continue, 0, 'No', 'Yes'),
                            'D_10_7_1_R_4' VALUE(
                        SELECT
                            nvl(
                                decode(stop_date_res,
                                       0,
                                       nvl(stop_date_nf, NULL),
                                       8,
                                       to_char(stop_date, 'YYYYMMDD'),
                                       5,
                                       to_char(stop_date, 'YYYY'),
                                       7,
                                       to_char(stop_date, 'YYYYMM')),
                                NULL
                            )
                        FROM
                            case_pat_hist,
                            case_pat_hist_nf
                        WHERE
                                case_pat_hist.case_id = case_pat_hist_nf.case_id(+)
                            AND case_pat_hist.seq_num = case_pat_hist_nf.seq_num(+)
                            AND case_pat_hist.case_id = cph.case_id
                            AND case_pat_hist.seq_num = cph.seq_num
                            AND case_pat_hist.deleted IS NULL
                            AND ROWNUM < 2
                    ),
                            'D_10_7_1_R_5' VALUE substr(
                        to_char(cph.note),
                        0,
                        1999
                    )
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master       cm,
            case_pat_hist     cph,
            lm_condition_type lm
        WHERE
                cm.case_id = l_case_id
            AND cph.case_id = cm.case_id
            AND lm.condition_type_id = cph.condition_type_id
            AND cph.parent = 1
            AND lm.condition_type_id = cph.condition_type_id
            AND lm.cond_category = 1
            AND cph.deleted IS NULL
            AND cm.deleted IS NULL
            AND lm.deleted IS NULL
        ORDER BY
            cph.seq_num;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"PARENT_MED_HIST_D_10_7_1":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || ' PARENT_MED_HIST_D_10_7_1-section - While generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;

    BEGIN
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cph.case_id,
                            'PAT_SEQ_NUM' VALUE cph.seq_num,
                            'D_10_8_R_1' VALUE cph.condition,
                            'D_10_8_R_2A' VALUE(
                        SELECT
                            nvl(identifier_version, NULL)
                        FROM
                            case_pat_hist
                        WHERE
                                identifier_type_id = 1
                            AND case_id = cm.case_id
                            AND parent = 1
                            AND seq_num = cph.seq_num
                            AND deleted IS NULL
                    ),
                            'D_10_8_R_2B' VALUE(
                        SELECT
                            nvl(identifier, NULL)
                        FROM
                            case_pat_hist
                        WHERE
                                identifier_type_id = 1
                            AND case_id = cm.case_id
                            AND parent = 1
                            AND seq_num = cph.seq_num
                            AND deleted IS NULL
                    ),
                            'D_10_8_R_3A' VALUE(
                        SELECT
                            nvl(identifier_version, NULL)
                        FROM
                            case_pat_hist
                        WHERE
                                identifier_type_id = 2
                            AND case_id = cm.case_id
                            AND parent = 1
                            AND seq_num = cph.seq_num
                            AND deleted IS NULL
                    ),
                            'D_10_8_R_3B' VALUE(
                        SELECT
                            nvl(identifier, NULL)
                        FROM
                            case_pat_hist
                        WHERE
                                identifier_type_id = 2
                            AND case_id = cm.case_id
                            AND parent = 1
                            AND seq_num = cph.seq_num
                            AND deleted IS NULL
                    ),
                            'D_10_8_R_4' VALUE(
                        SELECT
                            nvl(
                                decode(start_date_res,
                                       0,
                                       nvl(start_date_nf, NULL),
                                       8,
                                       to_char(start_date, 'YYYYMMDD'),
                                       5,
                                       to_char(start_date, 'YYYY'),
                                       7,
                                       to_char(start_date, 'YYYYMM')),
                                NULL
                            )
                        FROM
                            case_pat_hist,
                            case_pat_hist_nf
                        WHERE
                                case_pat_hist.case_id = case_pat_hist_nf.case_id(+)
                            AND case_pat_hist.seq_num = case_pat_hist_nf.seq_num(+)
                            AND case_pat_hist.case_id = cph.case_id
                            AND case_pat_hist.seq_num = cph.seq_num
                            AND deleted IS NULL
                    ),
                            'D_10_8_R_5' VALUE(
                        SELECT
                            nvl(
                                decode(stop_date_res,
                                       0,
                                       nvl(stop_date_nf, NULL),
                                       8,
                                       to_char(stop_date, 'YYYYMMDD'),
                                       5,
                                       to_char(stop_date, 'YYYY'),
                                       7,
                                       to_char(stop_date, 'YYYYMM')),
                                NULL
                            )
                        FROM
                            case_pat_hist,
                            case_pat_hist_nf
                        WHERE
                                case_pat_hist.case_id = case_pat_hist_nf.case_id(+)
                            AND case_pat_hist.seq_num = case_pat_hist_nf.seq_num(+)
                            AND case_pat_hist.case_id = cph.case_id
                            AND case_pat_hist.seq_num = cph.seq_num
                            AND case_pat_hist.deleted IS NULL
                    ),
                            'D_10_8_R_6A' VALUE(
                        SELECT
                            substr(version_number, 1, 4)
                        FROM
                            cfg_dictionaries
                        WHERE
                                dict_id = cph.ind_dict_id
                            AND deleted IS NULL
                    ),
                            'D_10_8_R_6B' VALUE cph.ind_llt_code,
                            'D_10_8_R_7A' VALUE(
                        SELECT
                            substr(version_number, 1, 4)
                        FROM
                            cfg_dictionaries
                        WHERE
                                dict_id = cph.react_dict_id
                            AND deleted IS NULL
                    ),
                            'D_10_8_R_7B' VALUE cph.react_llt_code
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master       cm,
            case_pat_hist     cph,
            lm_condition_type lm
        WHERE
                cm.case_id = l_case_id
            AND cph.case_id = cm.case_id
            AND cph.parent = 1
            AND lm.condition_type_id = cph.condition_type_id
            AND lm.cond_category = 2
            AND cph.deleted IS NULL
            AND cm.deleted IS NULL
        ORDER BY
            cph.seq_num;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"PARENT_PAST_HIST_D_10_8":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || ' PARENT_PAST_HIST_D_10_8-section - While generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;

    BEGIN
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                            'SEQ_NUM_DEATH_DETAILS' VALUE cdd.seq_num,
                            'D_9_4_R_1A' VALUE nvl((
                        SELECT
                            substr(version_number, 1, 4)
                        FROM
                            cfg_dictionaries
                        WHERE
                                dict_id = cdd.cause_dict
                            AND deleted IS NULL
                    ),
                                                   NULL),
                            'D_9_4_R_1B' VALUE cdd.cause_llt_code,
                            'D_9_4_R_2' VALUE cdd.cause_reptd,
                            'D_9_4_R_1B_HLT_CODE' VALUE cdd.cause_hlt_code,
                            'D_9_4_R_1B_HLGT_CODE' VALUE cdd.cause_hlgt_code,
                            'D_9_4_R_1B_PT_CODE' VALUE cdd.cause_code,
                            'D_9_4_R_1B_SOC_CODE' VALUE cdd.cause_soc_code
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master        cm
            LEFT OUTER JOIN case_death_details cdd ON cdd.case_id = cm.case_id
                                                      AND cdd.term_type = 2 -- 1 - Cause of Death, 2 - Autopsy Result
            LEFT OUTER JOIN case_death         cd ON cd.autopsy IN ( 8, 9, 10 )
                                             AND cd.case_id = cdd.case_id
        WHERE
                cm.case_id = l_case_id
            AND cdd.deleted IS NULL
            AND cd.deleted IS NULL;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"AUTOPSY_INFO_D_9_4_R":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || ' AUTOSPY_INFO_D_9_4_R-section - While generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;

    BEGIN
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                            'SEQ_NUM_DEATH_DETAILS' VALUE cdd.seq_num,
                            'D_9_2_R_1A' VALUE(
                        SELECT
                            substr(version_number, 1, 4)
                        FROM
                            cfg_dictionaries
                        WHERE
                                dict_id = cdd.cause_dict
                            AND deleted IS NULL
                    ),
                            'D_9_2_R_1B' VALUE cdd.cause_llt_code,
                            'D_9_2_R_2' VALUE cdd.cause_reptd,
                            'D_9_2_R_1B_HLT_CODE' VALUE cdd.cause_hlt_code,
                            'D_9_2_R_1B_HLGT_CODE' VALUE cdd.cause_hlgt_code,
                            'D_9_2_R_1B_PT_CODE' VALUE cdd.cause_code,
                            'D_9_2_R_1B_SOC_CODE' VALUE cdd.cause_soc_code
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master        cm
            LEFT OUTER JOIN case_death_details cdd ON cdd.case_id = cm.case_id
                                                      AND cdd.term_type = 1
        WHERE
                cm.case_id = l_case_id
            AND cm.deleted IS NULL
            AND cdd.deleted IS NULL;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"DEATH_INFO_D_9_2_R":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || ' DEATH_INFO_D_9_2_R-section - While generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;

    BEGIN
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cph.case_id,
                            'SEQ_NUM' VALUE cph.seq_num,
                            'D_7_1_R_1A' VALUE(
                        SELECT
                            substr(version_number, 1, 4)
                        FROM
                            cfg_dictionaries
                        WHERE
                                dict_id = cph.item_dict
                            AND deleted IS NULL
                    ),
                            'D_7_1_R_1B' VALUE cph.item_llt_code,
                            'D_7_1_R_2' VALUE(
                        CASE
                            WHEN cphnf.start_date_nf IS NOT NULL
                                 AND cphnf.start_date_nf IN('ASKU', 'NASK') THEN
                                esm_mapping_utl.f_get_null_flavor(cphnf.start_date_nf)
                            WHEN start_date IS NOT NULL THEN
                                decode(start_date_res,
                                       5,
                                       to_char(start_date, 'YYYY'),
                                       7,
                                       to_char(start_date, 'YYYYMM'),
                                       8,
                                       to_char(start_date, 'YYYYMMDD'),
                                       NULL)
                            ELSE
                                NULL
                        END
                    ),
                            'D_7_1_R_3' VALUE decode(cph.continue, 1, 'true', 'false'),
                            'D_7_1_R_4' VALUE(
                        CASE
                            WHEN cphnf.stop_date_nf IS NOT NULL
                                 AND cphnf.stop_date_nf IN('ASKU', 'NASK') THEN
                                esm_mapping_utl.f_get_null_flavor(cphnf.stop_date_nf)
                            WHEN stop_date IS NOT NULL THEN
                                decode(stop_date_res,
                                       5,
                                       to_char(stop_date, 'YYYY'),
                                       7,
                                       to_char(stop_date, 'YYYYMM'),
                                       8,
                                       to_char(stop_date, 'YYYYMMDD'),
                                       NULL)
                            ELSE
                                NULL
                        END
                    ),
                            'D_7_1_R_5' VALUE substr(
                        to_char(cph.note),
                        0,
                        1999
                    ),
                            'D_7_1_R_6' VALUE cph.family_history,
                            'D_7_1_R_1B_HLT_CODE' VALUE cph.item_hlt_code,
                            'D_7_1_R_1B_HLGT_CODE' VALUE cph.item_hlgt_code,
                            'D_7_1_R_1B_PT_CODE' VALUE cph.item_code,
                            'D_7_1_R_1B_SOC_CODE' VALUE cph.item_soc_code
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master       cm,
            case_pat_hist     cph,
            case_pat_hist_nf  cphnf,
            lm_condition_type lm
        WHERE
                cph.case_id = cm.case_id
            AND cm.case_id = l_case_id
            AND cph.case_id = cphnf.case_id (+)
            AND cph.seq_num = cphnf.seq_num (+)
            AND lm.condition_type_id = cph.condition_type_id
            AND lm.cond_category = 1
            AND cph.parent = '0'
            AND cph.deleted IS NULL
        ORDER BY
            cph.seq_num;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"PAT_HIST_D_7_1":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || ' D_7_1-section - While generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;

    BEGIN
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cph.case_id,
                            'SEQNUM' VALUE cph.seq_num,
                            'D_8_R_1' VALUE cph.condition,
                            'D_8_R_2A' VALUE(
                        SELECT
                            nvl(identifier_version, NULL)
                        FROM
                            case_pat_hist
                        WHERE
                                identifier_type_id = 1
                            AND case_id = cm.case_id
                            AND parent = 0
                            AND seq_num = cph.seq_num
                            AND case_pat_hist.deleted IS NULL
                    ),
                            'D_8_R_2B' VALUE(
                        SELECT
                            nvl(identifier, NULL)
                        FROM
                            case_pat_hist
                        WHERE
                                identifier_type_id = 1
                            AND case_id = cm.case_id
                            AND parent = 0
                            AND seq_num = cph.seq_num
                            AND case_pat_hist.deleted IS NULL
                    ),
                            'D_8_R_3A' VALUE(
                        SELECT
                            nvl(identifier_version, NULL)
                        FROM
                            case_pat_hist
                        WHERE
                                identifier_type_id = 2
                            AND case_id = cm.case_id
                            AND parent = 0
                            AND seq_num = cph.seq_num
                            AND case_pat_hist.deleted IS NULL
                    ),
                            'D_8_R_3B' VALUE(
                        SELECT
                            nvl(identifier, NULL)
                        FROM
                            case_pat_hist
                        WHERE
                                identifier_type_id = 2
                            AND case_id = cm.case_id
                            AND parent = 0
                            AND seq_num = cph.seq_num
                            AND case_pat_hist.deleted IS NULL
                    ),
                            'D_8_R_4' VALUE(
                        CASE
                            WHEN cphnf.start_date_nf IS NOT NULL
                                 AND cphnf.start_date_nf IN('ASKU', 'NASK') THEN
                                esm_mapping_utl.f_get_null_flavor(cphnf.start_date_nf)
                            WHEN cph.start_date IS NOT NULL
                                 AND cph.start_date_res IN(5, 7, 8) THEN
                                decode(cph.start_date_res,
                                       5,
                                       to_char(cph.start_date, 'YYYY'),
                                       7,
                                       to_char(cph.start_date, 'YYYYMM'),
                                       8,
                                       to_char(cph.start_date, 'YYYYMMDD'),
                                       NULL)
                            ELSE
                                NULL
                        END
                    ),
                            'D_8_R_5' VALUE(
                        CASE
                            WHEN cphnf.stop_date_nf IS NOT NULL
                                 AND cphnf.stop_date_nf IN('ASKU', 'NASK') THEN
                                esm_mapping_utl.f_get_null_flavor(cphnf.stop_date_nf)
                            WHEN cph.stop_date IS NOT NULL
                                 AND cph.stop_date_res IN(5, 7, 8) THEN
                                decode(cph.stop_date_res,
                                       5,
                                       to_char(cph.stop_date, 'YYYY'),
                                       7,
                                       to_char(cph.stop_date, 'YYYYMM'),
                                       8,
                                       to_char(cph.stop_date, 'YYYYMMDD'),
                                       NULL)
                            ELSE
                                NULL
                        END
                    ),
                            'D_8_R_6A' VALUE(
                        SELECT
                            substr(version_number, 1, 4)
                        FROM
                            cfg_dictionaries
                        WHERE
                                dict_id = cph.ind_dict_id
                            AND deleted IS NULL
                    ),
                            'D_8_R_6B' VALUE cph.ind_llt_code,
                            'D_8_R_7A' VALUE(
                        SELECT
                            substr(version_number, 1, 4)
                        FROM
                            cfg_dictionaries
                        WHERE
                                dict_id = cph.react_dict_id
                            AND deleted IS NULL
                    ),
                            'D_8_R_7B' VALUE cph.react_llt_code
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master       cm,
            case_pat_hist     cph,
            case_pat_hist_nf  cphnf,
            lm_condition_type lm
        WHERE
                cph.case_id = cm.case_id (+)
            AND cm.case_id = l_case_id
            AND cph.case_id = cphnf.case_id (+)
            AND cph.seq_num = cphnf.seq_num (+)
            AND cph.condition_type_id = lm.condition_type_id (+)
            AND lm.cond_category = 2
            AND cph.parent = '0'
            AND cm.deleted IS NULL
            AND cph.deleted IS NULL
        ORDER BY
            cph.seq_num;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"PAT_PAST_DRUG_D_8_R":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || ' PAST_DRUG_D_8_R - While generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;
    /*************************************************E-section**********************************************/
    BEGIN
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                            'EVENT_SEQ_NUM' VALUE ce.seq_num,
                            'E_I_1_1A' VALUE ce.desc_reptd,
                            'E_I_1_1B_LANGUAGE_ID' VALUE(
                        SELECT
                            language_id
                        FROM
                            case_language
                        WHERE
                                case_id = cm.case_id
                            AND field_id = 1150309
                            AND deleted IS NULL
                    ),
                            'E_I_1_2' VALUE ce.desc_reptd,
                            'E_I_2_1A' VALUE(
                        SELECT
                            substr(version_number, 1, 4)
                        FROM
                            cfg_dictionaries
                        WHERE
                                dict_id = ce.dict_id
                            AND deleted IS NULL
                    ),
                            'E_I_2_1B' VALUE ce.inc_code,
                            'E_I_2_1B_PT_CODE' VALUE ce.art_code,
                            'E_I_2_1B_HLT_CODE' VALUE ce.hlt_code,
                            'E_I_2_1B_HLGT_CODE' VALUE ce.hlgt_code,
                            'E_I_2_1B_SOC_CODE' VALUE ce.soc_code,
                            'E_I_3_1' VALUE ce.rpt_serious,
                            'CASE_SERIOUS' VALUE(
                        SELECT
                            seriousness
                        FROM
                            case_assess
                        WHERE
                                case_id = cm.case_id
                            AND deleted IS NULL
                    ),
                            'E_I_3_2A' VALUE decode(ce.sc_death, 1, 'true', 0, 'false',
                                                    NULL),
                            'E_I_3_2B' VALUE decode(ce.sc_threat, 1, 'true', 0, 'false',
                                                    NULL),
                            'E_I_3_2C' VALUE decode(ce.sc_hosp, 1, 'true', 0, 'false',
                                                    NULL),
                            'E_I_3_2D' VALUE decode(ce.sc_disable, 1, 'true', 0, 'false',
                                                    NULL),
                            'E_I_3_2E' VALUE decode(ce.sc_cong_anom, 1, 'true', 0, 'false',
                                                    NULL),
                            'E_I_3_2F' VALUE(
                        CASE
                            WHEN sc_other = 1    THEN
                                'true'
                            WHEN med_serious = 1 THEN
                                'true'
                            WHEN sc_int_req = 1  THEN
                                'true'
                        END
                    ),
                            'E_I_4' VALUE(nvl(
                        decode(onset_res,
                               0,
                               nvl(onset_nf, NULL),
                               8,
                               to_char(ce.onset, 'YYYYMMDD'),
                               5,
                               to_char(ce.onset, 'YYYY'),
                               7,
                               to_char(ce.onset, 'YYYYMM')),
                        NULL
                    )),
                            'E_I_5' VALUE(decode(ce.stop_date_res,
                                                 0,
                                                 nvl(cnf.stop_date_nf, NULL),
                                                 5,
                                                 to_char(ce.stop_date, 'YYYY'),
                                                 7,
                                                 to_char(ce.stop_date, 'YYYYMM'),
                                                 8,
                                                 to_char(ce.stop_date, 'YYYYMMDD'),
                                                 NULL)),
                            --'E_I_6A' VALUE SUBSTR(ce.duration_seconds,0,5),
                            --'E_I_6B' VALUE ce.duration_unit_e2b,
                            'E_I_6A' VALUE esm_utl.f_duration(ce.duration_seconds, duration),
                            'E_I_6B' VALUE esm_mapping_utl.f_duration_unit_r3(duration_seconds, duration),
                            'E_I_7' VALUE(
                        SELECT
                            nvl(display_value, NULL)
                        FROM
                            code_list_detail_discrete
                        WHERE
                                code_list_id = 'EVENT_OUTCOME'
                            AND decode_context = 'E2B_R3'
                            AND code = ce.evt_outcome_id
                    ),
                            'E_I_8' VALUE decode(ce.medical_confirm, 1, 'true', 0, 'false',
                                                 NULL),
                            'E_I_9' VALUE(
                        SELECT DISTINCT
                            lc.a2
                        FROM
                            lm_countries lc
                        WHERE
                                lc.country_id = ce.country_occured_id
                            AND lc.deleted IS NULL
                    ),
                            'E_I_INTENSITY' VALUE(
                        SELECT
                            evt_intensity
                        FROM
                            lm_evt_intensity l
                        WHERE
                                l.evt_intensity_id = ce.evt_intensity_id
                            AND l.deleted IS NULL
                    ),
                            'E_I_ONSET_LATENCY' VALUE ce.onset_latency,
                            'SORT_ORDER' VALUE ce.sort_id
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master   cm, case_event    ce
            LEFT OUTER JOIN case_event_nf cnf ON cnf.case_id = ce.case_id
                                                 AND cnf.seq_num = ce.seq_num
        WHERE
                ce.case_id = cm.case_id
            AND cm.case_id = l_case_id
            AND ce.deleted IS NULL
            AND cm.deleted IS NULL
        ORDER BY
            ce.seq_num ASC;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"EVENTS_E":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || 'E section - While generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;
    /*************************************************H-section**********************************************/
    BEGIN
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cn.case_id,
                    'H_1' VALUE cn.narrative,
                    'H_2' VALUE cc.comment_txt,
                    'H_4' VALUE cts.comment_txt
                RETURNING CLOB)
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master       cm
            LEFT JOIN case_narrative    cn ON cn.case_id = cm.case_id
            LEFT JOIN case_comments     cc ON cc.case_id = cm.case_id
            LEFT JOIN case_company_cmts cts ON cts.case_id = cm.case_id
        WHERE
                cm.case_id = l_case_id
            AND cm.deleted IS NULL;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"NARRATIVES_H":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                            'H_3_R_1A' VALUE nvl((
                        SELECT
                            substr(version_number, 1, 4)
                        FROM
                            cfg_dictionaries
                        WHERE
                                dict_id = ca.diagnosis_dict_id
                            AND deleted IS NULL
                    ),
                                                 NULL),
                            'H_3_R_1B' VALUE nvl(ca.diagnosis_inc_code, NULL)
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master cm,
            case_assess ca
        WHERE
                cm.case_id = l_case_id
            AND ca.case_id = cm.case_id
            AND cm.deleted IS NULL
            AND ca.deleted IS NULL;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"NARRATIVES_H3":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                            'H_5_R_1A' VALUE nvl(cc.comment_txt_j, NULL),
                            'H_5_R_1B' VALUE nvl(cl.language_id, NULL)
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master   cm,
            case_language cl,
            case_comments cc
        WHERE
                cm.case_id = l_case_id
            AND cc.case_id = cm.case_id
            AND cl.case_id = cm.case_id
            AND cl.language_id <> 1
            AND cl.deleted IS NULL
            AND cc.deleted IS NULL
            AND cm.deleted IS NULL;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"NARRATIVES_H5":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || ' H section While generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;
    /*************************************************F-section**********************************************/
    BEGIN
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cld.case_id,
                            'SEQ_NUM' VALUE cld.seq_num,
                            'F_R_1' VALUE nvl(
                        decode(cld.test_date_res,
                               8,
                               to_char(cld.test_date, 'YYYYMMDD'),
                               7,
                               to_char(cld.test_date, 'YYYYMM'),
                               5,
                               to_char(cld.test_date, 'YYYY')),
                        NULL
                    ),
                            'F_R_2_1' VALUE cld.lab_test_name,
                            'F_R_2_2A' VALUE(
                        SELECT
                            substr(version_number, 1, 4)
                        FROM
                            cfg_dictionaries
                        WHERE
                                dict_id = cld.dict_id
                            AND deleted IS NULL
                    ),
                            'F_R_2_2B' VALUE cld.llt_code,
                            'F_R_3_1' VALUE cld.assessment,
                            'F_R_3_2' VALUE cld.results,
                            'F_R_3_3' VALUE cld.unit,
                            'F_R_3_4' VALUE substr(
                        to_char(cld.notes),
                        0,
                        1999
                    ),
                            'F_R_4' VALUE cld.norm_low,
                            'F_R_5' VALUE cld.norm_high,
                            'F_R_7' VALUE decode(cld.info_available, 1, 'Yes', 'No'),
                            'F_R_6' VALUE substr(
                        to_char(cld.comments),
                        0,
                        1999
                    )
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master   cm,
            case_lab_data cld
        WHERE
                cm.case_id = l_case_id
            AND cld.case_id = cm.case_id
            AND cm.deleted IS NULL
            AND cld.deleted IS NULL
        ORDER BY
            cld.case_id,
            cld.seq_num;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"LAB_F_R":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || ' F- section While generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;
    -----------------------------------------------------G Section-------------------------------------------------------
    BEGIN
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                            'PRODUCT_SEQ_NUM' VALUE cp.seq_num,
				            -- 'PRODUCT_ID' VALUE nvl(cp.product_id, cp.pat_exposure),
				            -- HLP-7103
                            'DRUG_NAME_OVERRIDE' VALUE cp.prod_coded,
                            'G_K_1' VALUE
                        CASE
                            WHEN cp.sdrug_not_admin = 1 THEN
                                4
                            WHEN cpd.interaction = 1    THEN
                                3
                            ELSE
                                cp.drug_type
                        END,
                            'PRODUCT_TYPE' VALUE decode(cp.selected_view, 1, 1, 2, 3,
                                                        3, 2, NULL),
				            -- 'G_K_1_SDRUG_NOT_ADMIN' VALUE cp.sdrug_not_admin,
				            -- 'G_K_1_INTERACTION' VALUE cpd.interaction,
                            'MIGRATION_DRUG_CODE' VALUE(nvl(cp.product_id, cp.pat_exposure)),
                            'MIGRATION_DRUG_TYPE' VALUE 'P',
                            'G_K_2_2' VALUE
                        CASE
                            WHEN upper(cp.co_drug_code) = 'STUDY DRUG'
                                 AND(nvl(cs.code_broken, 0) > 0) THEN
                                 
                                    -- Pre. Argus 8.2.3
                                    substr(cp.product_name, 1, 250) END, --RRR
								 
                                 /* 
                                         -- Argus 8.2.3 feature
                                            CASE
                                                WHEN nvl(cs.code_broken, 0) = 4 THEN
                                                    
                                                    
                                                    
                                                    substr(
                                                        esm_mapping_utl.f_get_medicinalproduct(
                                                            nvl(cp.product_id, cp.pat_exposure),
                                                            cp.seq_num,
                                                            cp.co_drug_code,
                                                            cp.pat_exposure,
                                                            cp.product_name
                                                        ),
                                                        1,
                                                        250
                                                    )
                                                    
                                                ELSE
                                                    substr(lmp.prod_name, 1, 250)
                                            END
                                            substr(lmp.prod_name, 1, 250)
                                    ELSE 						                            
                                END*/
                                -- End Argus 8.2.3 feature 	
                            
                            'RPT_TYPE_ID' VALUE cm.rpt_type_id,
                            'G_K_2_4' VALUE(nvl(lc.a2, NULL)),
                            'G_K_2_5' VALUE(
                        CASE
                            WHEN upper(cp.co_drug_code) = upper('Study Drug')
                                 AND nvl(cs.code_broken, 0) = 0 THEN
                                'true'
                            ELSE
                                'false'
                        END
                    ),
                
                /*
                Added new fields:
                G_K_2_1_1A 		>> MPID Version Date / Number
                G_k_2_1_2a 		>> PhPID Version Date/Number
                G_k_2_1_2b 		>> Pharmaceutical Product Identifier (PhPID)
                G_K_11 			>> Additional Information on Drug (free text)
                */
                            'G_K_2_1_1A' VALUE(
                        CASE
                            WHEN lpit.prod_identifier = 'MPID'
                                 AND cp.identifier_version IS NOT NULL
                                 AND cp.identifier IS NOT NULL THEN
                                cp.identifier_version
                            ELSE
                                NULL
                        END
                    ),
                            'G_k_2_1_2a' VALUE(
                        CASE
                            WHEN lpit.prod_identifier = 'PhPID'
                                 AND cp.identifier_version IS NOT NULL
                                 AND cp.identifier IS NOT NULL THEN
                                cp.identifier_version
                            ELSE
                                NULL
                        END
                    ),
                            'G_k_2_1_2b' VALUE(
                        CASE
                            WHEN lpit.prod_identifier = 'PhPID'
                                 AND cp.identifier_version IS NOT NULL
                                 AND cp.identifier IS NOT NULL THEN
                                regexp_replace(
                                    substr(cp.identifier, 1, 250),
                                    '[[:space:]]*',
                                    ''
                                )
                            ELSE
                                NULL
                        END
                    ),
                            'G_K_11' VALUE(esm_mapping_utl.get_r3_drugadditional(l_case_id, cp.seq_num, 2000)),
                            'G_K_3_1' VALUE(nvl(ll.lic_number, NULL)),
                            'G_K_3_2' VALUE(substr(lc.a2, 1, 2)),
                            'G_K_3_3' VALUE(nvl(lmn.manu_name, NULL)),
                            'G_K_5A' VALUE nvl(cpd.cumulative_dose, NULL),
                            'G_K_5B' VALUE(
                        SELECT
                            unit
                        FROM
                            lm_dose_units
                        WHERE
                            unit_id = cpd.cumulative_dose_unit_id
                    ),
                            'G_K_6A' VALUE nvl(cpd.exposure, NULL),
                            'G_K_6B' VALUE(
                        SELECT
                            display_value
                        FROM
                            code_list_detail_discrete
                        WHERE
                                code_list_id = 'AGE_UNITS'
                            AND decode_context = 'UCUM_CODE'
                            AND code = cpd.exposure_unit_id
                    ),
                            'G_K_8' VALUE(
                        SELECT
                            display_value
                        FROM
                            code_list_detail_discrete
                        WHERE
                                code_list_id = 'ACTION_TAKEN'
                            AND decode_context = 'E2B_R3'
                            AND code = cpd.act_taken_id
                    ),
                            'SORT_ORDER' VALUE cp.sort_id
                )
            RETURNING CLOB) as
        INTO l_temp_str
        FROM
            case_prod_drugs            cpd,
            case_product               cp,
            case_master                cm,
            case_study                 cs,
            lm_license                 ll,
            lm_countries               lc,
            lm_manufacturer            lmn,
            lm_product_identifier_type lpit,
            lm_product                 lmp
        WHERE
                cp.case_id = cm.case_id
            AND cm.case_id = cs.case_id (+)
            AND cp.identifier_type_id = lpit.id (+)
            AND cp.case_id = cpd.case_id (+)
            AND cp.seq_num = cpd.seq_num (+)
            AND cpd.obtain_drug_country_id = lc.country_id (+)
            AND cm.case_id = l_case_id
            AND cp.prod_lic_id = ll.license_id (+)
            AND ll.country_id = lc.country_id (+)
            AND cp.manufacturer_id = lmn.manufacturer_id (+)
            AND nvl(cp.product_id, cp.pat_exposure) = lmp.product_id (+)
            AND lmp.deleted IS NULL
            AND ll.deleted IS NULL
            AND lmn.deleted IS NULL
            AND lc.deleted IS NULL
            AND cpd.deleted IS NULL
            AND cp.deleted IS NULL
            AND cm.deleted IS NULL;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"PRODUCT_G_K":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;
      ------------------------------------------------------------------------------------------------------------------
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                            'PRODUCT_ID' VALUE cp.product_id,
                            'SEQ_NUM' VALUE cpd.seq_num,
                            'PRODUCT_SEQ_NUM' VALUE cp.seq_num,
                            'G_K_4_R_10_1' VALUE(
                        SELECT
                            nvl(lar.route_desc, NULL)
                        FROM
                            lm_admin_route lar
                        WHERE
                                lar.admin_route_id = cdr.admin_route_id
                            AND deleted IS NULL
                    ),
                    
                            'G_K_4_R_10_2B' VALUE(get_lm_value('EDQM_TERM_ID', 'V$LM_ADMIN_ROUTE_EDQM', 'admin_route_id', cdr.admin_route_id
                            )),

                            
                            'G_K_4_R_11_1' VALUE nvl(cdr.par_admin_route, NULL),
                            'G_K_4_R_1A' VALUE
                        CASE
                            WHEN nvl(cdr.dose * nvl(ldf.separate_dosage_numb_e2b, 1),
                                         -1) > 0
                                 AND lmd.dose_units_ucum_code IS NOT NULL THEN
                                esm_utl.f_round_str(cdr.dose * nvl(ldf.separate_dosage_numb_e2b, 1),
                                                    8)
                        END,
                            'G_K_4_R_1B' VALUE
                        CASE
                            WHEN nvl(cdr.dose * nvl(ldf.separate_dosage_numb_e2b, 1),
                                         -1) > 0
                                 AND lmd.dose_units_ucum_code IS NOT NULL THEN
                                lmd.dose_units_ucum_code
                        END,
                            'G_K_4_R_4' VALUE(decode(start_datetime_res,
                                                     0,
                                                     cnf.start_datetime_nf,
                                                     8,
                                                     to_char(start_datetime, 'YYYYMMDD'),
                                                     5,
                                                     to_char(start_datetime, 'YYYY'),
                                                     7,
                                                     to_char(start_datetime, 'YYYYMM'))),
        --                       'G_K_4_R_4_NF' VALUE (SELECT START_DATETIME_NF FROM CASE_DOSE_REGIMENS_NF CNF WHERE CNF.CASE_ID=CM.CASE_ID AND CDR.LOG_NO=CNF.SEQ_NUM),
                            'G_K_4_R_5' VALUE(decode(stop_datetime_res,
                                                     0,
                                                     cnf.stop_datetime_nf,
                                                     8,
                                                     to_char(stop_datetime, 'YYYYMMDD'),
                                                     5,
                                                     to_char(stop_datetime, 'YYYY'),
                                                     7,
                                                     to_char(stop_datetime, 'YYYYMM'))),
        --                       'G_K_4_R_5_NF'  VALUE (SELECT STOP_DATETIME_NF FROM CASE_DOSE_REGIMENS_NF CNF WHERE CNF.CASE_ID=CM.CASE_ID AND CDR.LOG_NO=CNF.SEQ_NUM),
                            --'G_K_4_R_6A' VALUE substr(cdr.duration_seconds, 0,5),
                            --'G_K_4_R_6B' VALUE nvl(cdr.duration_seconds, NULL),
                            'G_K_4_R_6A' VALUE esm_utl.f_duration(cdr.duration_seconds, cdr.duration, 0),
                            'G_K_4_R_6B' VALUE esm_mapping_utl.get_r3_unit_for_r2(esm_utl.f_duration_unit(cdr.duration_seconds, cdr.duration
                            , 0)),
                            'G_K_4_R_7' VALUE(nvl(cdr.lot_no, cnf.lot_no_nf)),
                            'G_K_4_R_8' VALUE nvl(cdr.dose_description, NULL),
                            'G_K_4_R_9_1' VALUE(
                        SELECT
                            nvl(lf.formulation, NULL)
                        FROM
                            lm_formulation lf
                        WHERE
                                lf.formulation_id = cpd.formulation_id
                            AND deleted IS NULL
                    ),
                    
                        -- Argus 8.2.3 and later 
                        
                         /*   'G_K_4_R_9_2B' VALUE(
                        SELECT
                            nvl(lf.edqm_term_id, NULL)
                        FROM
                            v$lm_formulation_edqm lf
                        WHERE
                                lf.formulation_id = cpd.formulation_id
                            AND deleted IS NULL
                            AND ROWNUM < 2
                    ),
                    */
					
                    -- Pre. Argus 8.2.3
					 'G_K_4_R_9_2B' VALUE(get_lm_value('EDQM_TERM_ID', 'V$LM_FORMULATION_EDQM', 'formulation_id', cpd.formulation_id
                            )),
					
										
--                            'FREQUENCY_B_4_K_5_3' VALUE nvl(ldf.freq, NULL),
                            'FREQUENCY_B_4_K_5_3' VALUE(
                        SELECT
                            decode(
                                decode(elu.e2b_code, 807, NULL, 810, NULL,
                                       811, NULL, 812, NULL, 813,
                                       NULL, elu.e2b_code),
                                NULL,
                                NULL,
                                ldf.separate_dosage_numb_e2b
                            )
                        FROM
                            esm_lm_units elu
                        WHERE
                            ldf.interval_dosage_def_e2b = elu.id(+)
                    ),
                            'G_K_4_R_2' VALUE ldf.interval_dosage_unit_e2b,
                            'G_K_4_R_3' VALUE(
                        SELECT
                            display_value
                        FROM
                            code_list_detail_discrete
                        WHERE
                                code_list_id = 'INTERVAL_UNITS'
                            AND decode_context = 'UCUM_CODE'
                            AND code = ldf.interval_dosage_def_e2b
                    )
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master           cm, case_product          cp
            LEFT OUTER JOIN case_prod_drugs       cpd ON cp.case_id = cpd.case_id
                                                   AND cp.seq_num = cpd.seq_num
            LEFT OUTER JOIN case_dose_regimens    cdr ON cdr.case_id = cp.case_id
                                                      AND cdr.seq_num = cp.seq_num
            LEFT OUTER JOIN case_dose_regimens_nf cnf ON cdr.case_id = cnf.case_id
                                                         AND cdr.log_no = cnf.seq_num
            LEFT OUTER JOIN lm_dose_frequency     ldf ON cdr.freq_id = ldf.freq_id
            LEFT OUTER JOIN (
                SELECT
                    unit_id,
                    dose_units_ucum_code,
                    unit
                FROM
                    lm_dose_units
                WHERE
                    dosage_unit = 1
            )                     lmd ON cdr.dose_unit_id = lmd.unit_id
        WHERE
                cp.case_id = cm.case_id
            AND cm.case_id = l_case_id
            AND cm.deleted IS NULL
            AND cp.deleted IS NULL;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"PRODUCT_DOSE_G_K_4":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;
      ----------------------------------------------------------------------------------
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cp.case_id,
                            'G_K_2_2' VALUE cp.product_name,
                            'PRODUCT_SEQ_NUM' VALUE cp.seq_num,
                            'PRODUCT_ID' VALUE cp.product_id,
                            'G_K_7_R_1' VALUE decode(cnf.null_flavor_code, 2, 'ASKU', 3, 'NASK',
                                                     1, 'UNK', cpi.ind_reptd),
                            'G_K_7_R_2A' VALUE(
                        SELECT
                            substr(
                                listagg(version_number, ','),
                                0,
                                4
                            )
                        FROM
                            cfg_dictionaries
                        WHERE
                                dict_id = cpi.ind_code_dict
                            AND deleted IS NULL
                    ),
                            'G_K_7_R_2B' VALUE cpi.ind_llt_code
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master           cm, case_product          cp
            LEFT OUTER JOIN case_prod_indications cpi ON cpi.case_id = cp.case_id
                                                         AND cp.seq_num = cpi.prod_seq_num
            LEFT OUTER JOIN case_null_flavor      cnf ON cnf.case_id = cpi.case_id
                                                    AND cnf.field_id = 35550005
                                                    AND cpi.seq_num = cnf.seq_num
                                                    AND cnf.deleted IS NULL
        WHERE
                cp.case_id = cm.case_id
            AND cm.case_id = l_case_id
            AND cm.deleted IS NULL
            AND cp.deleted IS NULL
        ORDER BY
            cp.seq_num;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"PROD_INDICATION_G_K_7_R":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;
      --------------------------------------------------------------------------------
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cm.case_id,
                            'SEQ_NUM' VALUE cea.seq_num,
                            'EVENT_SEQ_NUM' VALUE cea.event_seq_num,
                            'PRODUCT_SEQ_NUM' VALUE cea.prod_seq_num,
                            'G_K_9_I_1' VALUE ce.desc_reptd,
                            'G_K_9_I_3_1A' VALUE esm_utl.f_dose_duration(ced.onset_latency_seconds), --ced.onset_latency_seconds,
                            'G_K_9_I_3_1B' VALUE esm_mapping_utl.get_r3_unit_for_r2(esm_utl.f_dose_duration_unit(ced.onset_latency_seconds
                            )), --ced.onset_latency,
                            'G_K_9_I_3_2A' VALUE esm_utl.f_dose_duration(ced.onset_delay_seconds), --ced.onset_delay_seconds,
                            'G_K_9_I_3_2B' VALUE esm_mapping_utl.get_r3_unit_for_r2(esm_utl.f_dose_duration_unit(ced.onset_delay_seconds
                            )),--ced.onset_delay,
                            'DECHALLENGE' VALUE(
                        SELECT
                            dechallenge
                        FROM
                            case_prod_drugs
                        WHERE
                                case_id = cm.case_id
                            AND seq_num = cp.seq_num
                    ),
                            'RECHALLENGE' VALUE(
                        SELECT
                            rechallenge
                        FROM
                            case_prod_drugs
                        WHERE
                                case_id = cm.case_id
                            AND seq_num = cp.seq_num
                    ),
                            'G_K_9_I_4' VALUE(
                        SELECT
                            CASE
                                WHEN cpd.rechallenge = 1
                                     AND ced.rechallenge = 1 THEN
                                    '1'
                                WHEN cpd.rechallenge = 1
                                     AND ced.rechallenge = 0 THEN
                                    '2'
                                WHEN cpd.rechallenge = 1
                                     AND ced.rechallenge = 2 THEN
                                    '3'
                                WHEN cpd.rechallenge = 0
                                     AND ced.rechallenge = 3 THEN
                                    '4'
                                ELSE
                                    NULL
                            END
                        FROM
                            case_prod_drugs cpd
                        WHERE
                                case_id = cm.case_id
                            AND seq_num = cp.seq_num
                            AND cpd.deleted IS NULL
                    ),
                            'G_K_9_I_2_R_3' VALUE
                                        -- Get R3 value (reportability - HALO accepts both binary / EU codes or text codes (must match HALO values)
                            (
                        SELECT
                            causality
                        FROM
                            lm_causality
                        WHERE
                            causality_id = cea.causality_id
                    ),
                            'G_K_9_I_2_R_1' VALUE(
                        SELECT
                            source
                        FROM
                            lm_causality_source
                        WHERE
                            source_id = cea.source_id
                    ),
                            'G_K_9_I_2_R_2' VALUE(
                        SELECT
                            method
                        FROM
                            lm_causality_method
                        WHERE
                            method_id = cea.method_id
                    ),
                            'LISTEDNESS' VALUE(
                        SELECT
                            decode(
                                max(decode(cea1.det_listedness_id, 1, 1, 2, 3,
                                           3, 2)),
                                1,
                                1,
                                3,
                                2,
                                2,
                                3
                            )
                        FROM
                            case_event_assess cea1
                        WHERE
                            cea1.det_causality_id IS NULL
                            AND cea1.case_id = l_case_id
                            AND cea1.deleted IS NULL
                            AND cea1.event_seq_num = ce.seq_num
                            AND cea1.prod_seq_num = cp.seq_num
                            AND cea1.datasheet_id <> 0
                    )
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master       cm,
        -- Make sure that we get two records - one for reported and one for determined causality
            (


                -- Determined causality
                SELECT
                    case_id,
                    seq_num,
                    event_seq_num,
                    prod_seq_num,
                    det_causality_id causality_id,
                    det_source_id    source_id,
                    det_method_id    method_id,
                    1                typ
                FROM
                    case_event_assess cea
                WHERE
                    cea.det_causality_id IS NOT NULL
                UNION ALL


                -- Reported causality
                SELECT
                    case_id,
                    seq_num,
                    event_seq_num,
                    prod_seq_num,
                    rpt_causality_id causality_id,
                    rpt_source_id    source_id,
                    rpt_method_id    method_id,
                    1                typ
                FROM
                    case_event_assess cea
                WHERE
                    cea.rpt_causality_id IS NOT NULL
            )                 cea,
            case_event_detail ced,
            case_product      cp,
            case_event        ce
        WHERE
                cm.case_id = l_case_id
            AND cea.case_id = cm.case_id
            AND cp.case_id = cm.case_id
            AND ce.case_id = cm.case_id
            AND ced.case_id = cm.case_id
            AND ce.seq_num = cea.event_seq_num
            AND cp.seq_num = cea.prod_seq_num
            AND cp.seq_num = ced.prod_seq_num
            AND ce.seq_num = ced.event_seq_num
            AND ced.deleted IS NULL
            AND cp.deleted IS NULL
            AND ce.deleted IS NULL
        ORDER BY
            cea.seq_num ASC;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"CAUSALITY_G_K_9_R":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

------------------------- LISTEDNESS ---------------------------------------------------------


        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE case_id,
                            'EVENT_SEQ_NUM' VALUE event_seq_num,
                            'PRODUCT_SEQ_NUM' VALUE prod_seq_num,
                            'DATASHEET_NAME' VALUE replace(
                        replace(sheet_name, '<', ''),
                        '>',
                        ''
                    ),
                            'LISTEDNESS' VALUE listedness_id
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            (
                SELECT DISTINCT
                    cea.case_id,
                    cea.event_seq_num,
                    cea.prod_seq_num,
                    ld.sheet_name,
                    cea.det_listedness_id listedness_id
                FROM
                    case_event_assess cea
                    LEFT JOIN lm_license        ll ON cea.license_id = ll.license_id
                    JOIN lm_countries      lc ON lc.country_id = ll.country_id
                    LEFT JOIN lm_datasheet      ld ON ld.datasheet_id = cea.datasheet_id
                    JOIN case_product      cp ON cp.seq_num = cea.prod_seq_num
                                            AND cp.case_id = cea.case_id
                    JOIN case_event        ce ON ce.seq_num = cea.event_seq_num
                                          AND ce.case_id = cea.case_id
                WHERE
                        cea.case_id = l_case_id
                    AND cea.rpt_causality_id IS NULL
                    AND cea.det_causality_id IS NULL
                    AND cea.deleted IS NULL
                    AND lc.deleted IS NULL
                    AND ll.deleted IS NULL
                    AND cp.deleted IS NULL
                    AND ce.deleted IS NULL
                GROUP BY
                    cea.case_id,
                    cea.event_seq_num,
                    cea.prod_seq_num,
                    ld.sheet_name,
                    cea.det_listedness_id
            );

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"LISTEDNESS":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

      -------------------------------------------------------------------------------------------------------------
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE cp.case_id,
                            'PRODUCT_SEQ_NUM' VALUE cp.seq_num,
                            'PRODUCT_ID' VALUE cp.product_id,
                            'G_K_2_3_R_1' VALUE(
                        SELECT
                            ingredient
                        FROM
                            lm_ingredients
                        WHERE
                                ingredient_id = cpi.ingredient_id
                            AND deleted IS NULL
                    ),

/*
Added below elements:
G_k_2_3_r_2a >> Substance/Specified Substance TermID Version Date/Number
G_k_2_3_r_2b >> Substance/Specified Substance TermID
*/
                            'G_K_2_3_R_2A' VALUE(
                        CASE
                            WHEN lpit.prod_identifier IN('MPID', 'PhPID')
                                 AND cp.identifier_version IS NOT NULL
                                 AND cp.identifier IS NOT NULL THEN
                                NULL
                            WHEN cpi.term_id IS NOT NULL
                                 AND cpi.term_id_version IS NOT NULL THEN
                                cpi.term_id_version
                            ELSE
                                NULL
                        END
                    ),
                            'G_K_2_3_R_2B' VALUE(
                        CASE
                            WHEN lpit.prod_identifier IN('MPID', 'PhPID')
                                 AND cp.identifier_version IS NOT NULL
                                 AND cp.identifier IS NOT NULL THEN
                                NULL
                            WHEN cpi.term_id IS NOT NULL
                                 AND cpi.term_id_version IS NOT NULL THEN
                                regexp_replace(cpi.term_id, '[[:space:]]*', '')
                            ELSE
                                NULL
                        END
                    ),
                            'G_K_2_3_R_3A' VALUE nvl(cpi.concentration, NULL),
                            'G_K_2_3_R_3B' VALUE(
                        SELECT
                            display_value
                        FROM
                            code_list_detail_discrete
                        WHERE
                                code_list_id = 'DOSE_UNITS'
                            AND decode_context = 'UCUM_CODE'
                            AND code = cpi.conc_unit_id
                    )
                )
            RETURNING CLOB)
        INTO l_temp_str
        FROM
            case_master                cm,
            case_product               cp,
            case_prod_ingredient       cpi,
            lm_product_identifier_type lpit
        WHERE
                cp.case_id = cm.case_id
            AND cp.case_id = cpi.case_id
            AND cp.seq_num = cpi.seq_num
            AND cp.identifier_type_id = lpit.id (+)
            AND cm.case_id = l_case_id
            AND cm.deleted IS NULL
            AND cp.deleted IS NULL
            AND cpi.deleted IS NULL
        ORDER BY
            cp.seq_num ASC;

        IF l_temp_str IS NOT NULL THEN
            dbms_lob.append(l_json_request,
                            to_clob(',"INGR_G_K_2_3_R":'));
            dbms_lob.append(l_json_request,
                            to_clob(l_temp_str));
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || ' G section - While generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;
------------------------------------------------------------------------------------------------------------------
-- G_K_10_R Starts --

    SELECT
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'SEQ_NUM' VALUE ROWNUM,
                'PRODUCT_SEQ_NUM' VALUE seq_num,
                'G_K_10_R' VALUE pa.value
            RETURNING CLOB)
        RETURNING CLOB)
    INTO l_temp_str
    FROM
        product_anamoly pa,
        (
            SELECT
                col_name,
                col_val,
                seq_num
            FROM
                case_prod_drugs UNPIVOT ( col_val
                    FOR col_name
                IN ( counterfeit,
                     overdose,
                     taken_by_father,
                     beyond_expired,
                     batch_in_spec,
                     batch_out_spec,
                     medication_error,
                     misuse,
                     abuse,
                     occupational_exp,
                     off_label_use ) )
            WHERE
                    case_id = l_case_id
                AND col_val > 0
        )               cpa
    WHERE
        pa.key = cpa.col_name;

    IF l_temp_str IS NOT NULL THEN
        dbms_lob.append(l_json_request,
                        to_clob(',"ADD_INFO_DRUG_G_K_10_R":'));
        dbms_lob.append(l_json_request,
                        to_clob(l_temp_str));
    END IF;

------------------------------------------------------------------------------------------------------------------


   ------------------- Device Information Starts ---------------------

    SELECT
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'CASE_ID' VALUE cm.case_id,
                        'SEQ_NUM' VALUE cpd.seq_num,
                        'PRODUCT_SEQ_NUM' VALUE cp.seq_num,
                        'B_4_K_20_FDA_17' VALUE decode(cpd.malfunction, NULL, NULL, 1, 1,
                                                       2),
                        'B_4_K_2_4_FDA_1A' VALUE decode(cpd.exp_date,
                                                        NULL,
                                                        NULL,
                                                        decode(cpd.exp_date_res, 5, 602, 7, 610,
                                                               102)),
                        'B_4_K_2_4_FDA_1B' VALUE decode(cpd.exp_date_res,
                                                        5,
                                                        to_char(cpd.exp_date, 'YYYY'),
                                                        7,
                                                        to_char(cpd.exp_date, 'YYYYMM'),
                                                        8,
                                                        to_char(cpd.exp_date, 'YYYYMMDD'),
                                                        NULL),
                        'B_4_K_2_FDA_5' VALUE decode(cpd.evaluation, 0, 2, 2, 3,
                                                     cpd.evaluation),
                        'B_4_K_2_6_FDA_1A' VALUE decode(cpd.return_date, NULL, NULL, 102),
                        'B_4_K_2_6_FDA_1B' VALUE decode(cpd.return_date,
                                                        NULL,
                                                        NULL,
                                                        to_char(cpd.return_date, 'YYYYMMDD')),
                        'B_4_K_20_FDA_1' VALUE cp.product_name,
                        'B_4_K_20_FDA_2' VALUE substr(ldt.device_type_desc, 1, 80),
                        'B_4_K_20_FDA_3' VALUE substr(lp.device_code, 1, 3),
                        'B_4_K_20_FDA_5' VALUE substr(cpd.model_no, 1, 30),
                        'B_4_K_20_FDA_6' VALUE substr(cpd.catalog, 1, 30),
                        'B_4_K_20_FDA_7' VALUE substr(cpd.serial_no, 1, 30),
                        'B_4_K_20_FDA_8' VALUE substr(
                    nvl(cpd.udi_di, cpd.catalog_other),
                    1,
                    50
                ),
                        'B_4_K_20_FDA_9A' VALUE decode(cpd.date_implant,
                                                       NULL,
                                                       NULL,
                                                       decode(cpd.date_impant_res, 5, 602, 7, 610,
                                                              102)),
                        'B_4_K_20_FDA_9B' VALUE decode(cpd.date_impant_res,
                                                       8,
                                                       to_char(cpd.date_implant, 'YYYYMMDD'),
                                                       7,
                                                       to_char(cpd.date_implant, 'YYYYMM'),
                                                       5,
                                                       to_char(cpd.date_implant, 'YYYY'),
                                                       NULL),
                        'B_4_K_20_FDA_10A' VALUE decode(cpd.date_explant,
                                                        NULL,
                                                        NULL,
                                                        decode(cpd.date_explant_res, 5, 602, 7, 610,
                                                               102)),
                        'B_4_K_20_FDA_10B' VALUE decode(cpd.date_explant_res,
                                                        8,
                                                        to_char(cpd.date_explant, 'YYYYMMDD'),
                                                        7,
                                                        to_char(cpd.date_explant, 'YYYYMM'),
                                                        5,
                                                        to_char(cpd.date_explant, 'YYYY'),
                                                        NULL),
                        'B_4_K_20_FDA_11A' VALUE
                    CASE
                        WHEN nvl(cpd.age, 0) > 0
                             AND nvl(cpd.age_unit_id, 0) > 0
                             AND lau.device_age_unit = 1 THEN
                            cpd.age
                        ELSE
                            NULL
                    END,
                        'B_4_K_20_FDA_11B' VALUE
                    CASE
                        WHEN nvl(cpd.age, 0) > 0
                             AND nvl(cpd.age_unit_id, 0) > 0
                             AND lau.device_age_unit = 1 THEN
                            lau.e2b_code
                        ELSE
                            NULL
                    END,
                        'B_4_K_20_FDA_12' VALUE decode(ll.single_use, 0, 2, 1),
                        'B_4_K_20_FDA_13A' VALUE decode(cpd.mfg_date,
                                                        NULL,
                                                        NULL,
                                                        decode(cpd.mfg_date_res, 5, 602, 7, 610,
                                                               102)),
                        'B_4_K_20_FDA_13B' VALUE decode(cpd.mfg_date_res,
                                                        8,
                                                        to_char(cpd.mfg_date, 'YYYYMMDD'),
                                                        7,
                                                        to_char(cpd.mfg_date, 'YYYYMM'),
                                                        5,
                                                        to_char(cpd.mfg_date, 'YYYY')),
                        'B_4_K_20_FDA_15' VALUE cpd.dev_usage,
                        'B_4_K_20_FDA_20' VALUE substr(
                    decode(
                        upper(lo.device_operator),
                        'HCP',
                        'Health Professional',
                        'PATIENT',
                        'Lay User/Patient',
                        'OTHER',
                        decode(cpd.dev_oper_other_text, NULL, 'Other', cpd.dev_oper_other_text),
                        NULL,
                        cpd.dev_oper_other_text,
                        NULL
                    ),
                    1,
                    100
                ),
                        'B_4_K_20_FDA_18_1A' VALUE
                    CASE
                        WHEN bitand(cpd.followup_type, 16) = 16 THEN
                            1
                        ELSE
                            2
                    END,
                        'B_4_K_20_FDA_18_1B' VALUE
                    CASE
                        WHEN bitand(cpd.followup_type, 32) = 32 THEN
                            1
                        ELSE
                            2
                    END,
                        'B_4_K_20_FDA_18_1C' VALUE
                    CASE
                        WHEN bitand(cpd.followup_type, 64) = 64 THEN
                            1
                        ELSE
                            2
                    END,
                        'B_4_K_20_FDA_18_1D' VALUE
                    CASE
                        WHEN bitand(cpd.followup_type, 128) = 128 THEN
                            1
                        ELSE
                            2
                    END,
                        'B_4_K_20_FDA_4A' VALUE substr(lm.manu_name, 1, 100),
                        'B_4_K_20_FDA_4B' VALUE substr(lm.address, 1, 100),
                        'B_4_K_20_FDA_4C' VALUE substr(lm.city, 1, 35),
                        'B_4_K_20_FDA_4D' VALUE substr(lm.state, 1, 40),
                        'B_4_K_20_FDA_4E' VALUE lc.a2,
                        'B_4_K_20_FDA_14_1A' VALUE
                    CASE
                        WHEN bitand(
                            nvl(cpd.remedial_action, 0),
                            1
                        ) = 1 THEN
                            1
                        ELSE
                            2
                    END,
                        'B_4_K_20_FDA_14_1B' VALUE
                    CASE
                        WHEN bitand(
                            nvl(cpd.remedial_action, 0),
                            2
                        ) = 2 THEN
                            1
                        ELSE
                            2
                    END,
                        'B_4_K_20_FDA_14_1C' VALUE
                    CASE
                        WHEN bitand(
                            nvl(cpd.remedial_action, 0),
                            4
                        ) = 4 THEN
                            1
                        ELSE
                            2
                    END,
                        'B_4_K_20_FDA_14_1D' VALUE
                    CASE
                        WHEN bitand(
                            nvl(cpd.remedial_action, 0),
                            8
                        ) = 8 THEN
                            1
                        ELSE
                            2
                    END,
                        'B_4_K_20_FDA_14_1E' VALUE
                    CASE
                        WHEN bitand(
                            nvl(cpd.remedial_action, 0),
                            16
                        ) = 16 THEN
                            1
                        ELSE
                            2
                    END,
                        'B_4_K_20_FDA_14_1F' VALUE
                    CASE
                        WHEN bitand(
                            nvl(cpd.remedial_action, 0),
                            32
                        ) = 32 THEN
                            1
                        ELSE
                            2
                    END,
                        'B_4_K_20_FDA_14_1G' VALUE
                    CASE
                        WHEN bitand(
                            nvl(cpd.remedial_action, 0),
                            64
                        ) = 64 THEN
                            1
                        ELSE
                            2
                    END,
                        'B_4_K_20_FDA_14_1H' VALUE
                    CASE
                        WHEN bitand(
                            nvl(cpd.remedial_action, 0),
                            128
                        ) = 128 THEN
                            1
                        ELSE
                            2
                    END,
                        'B_4_K_20_FDA_14_1I' VALUE substr(cpd.remedial_other, 1, 75)
            RETURNING CLOB)
        RETURNING CLOB)
    INTO l_temp_str
    FROM
        case_master          cm,
        case_prod_devices    cpd,
        case_product         cp,
        lm_product           lp,
        lm_manufacturer      lm,
        lm_device_type       ldt,
        lm_age_units         lau,
        lm_license           ll,
        lm_countries         lc,
        lm_occupations       lo,
        case_prod_dev_patdev cpdp,
        case_prod_dev_eval   cpde,
        lm_lic_products      llp
    WHERE
            cm.case_id = cp.case_id
        AND cp.case_id = cpd.case_id (+)
        AND cpd.case_id = cpdp.case_id (+)
        AND cpd.case_id = cpde.case_id (+)
        AND cp.seq_num = cpd.seq_num (+)
        AND cp.seq_num = cpdp.prod_seq_num (+)
        AND cp.seq_num = cpde.prod_seq_num (+)
        AND llp.product_id = lp.product_id
        AND llp.license_id = ll.license_id
        AND cp.product_id = lp.product_id (+)
        AND cp.manufacturer_id = lm.manufacturer_id (+)
        AND cpd.device_type = ldt.device_type_id (+)
        AND cpd.age_unit_id = lau.age_unit_id (+)
        AND cp.prod_lic_id = ll.license_id (+)
        AND lm.country_id = lc.country_id (+)
        AND cpd.dev_oper = lo.occupation_id (+)
        AND cm.case_id = l_case_id;

    IF l_temp_str IS NOT NULL THEN
        dbms_lob.append(l_json_request,
                        to_clob(',"DEVICE_INFO_B_4_K_FDA":'));
        dbms_lob.append(l_json_request,
                        to_clob(l_temp_str));
    END IF;


--------------------------------------------------------------------------


    SELECT
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'SEQ_NUM' VALUE devseq,
                'PRODUCT_SEQ_NUM' VALUE prod_seq_num,
                'B_4_K_20_FDA_19_1A' VALUE etype,
                'B_4_K_20_FDA_19_1B' VALUE evalue
            RETURNING CLOB)
        RETURNING CLOB)
    INTO l_temp_str
    FROM
        (
            SELECT
                '01'       etype,
                fda_dev_cd evalue,
                seq_num    devseq,
                prod_seq_num
            FROM
                case_prod_dev_patdev
            WHERE
                case_id = l_case_id
            UNION
            SELECT
                '02'    etype,
                meth_cd evalue,
                seq_num devseq,
                prod_seq_num
            FROM
                case_prod_dev_eval
            WHERE
                case_id = l_case_id
            UNION
            SELECT
                '03'    etype,
                res_cd  evalue,
                seq_num devseq,
                prod_seq_num
            FROM
                case_prod_dev_eval
            WHERE
                case_id = l_case_id
            UNION
            SELECT
                '04'    etype,
                conc_cd evalue,
                seq_num devseq,
                prod_seq_num
            FROM
                case_prod_dev_eval
            WHERE
                case_id = l_case_id
        ) devevaluation
    ORDER BY
        devevaluation.etype,
        devevaluation.devseq;

    IF l_temp_str IS NOT NULL THEN
        dbms_lob.append(l_json_request,
                        to_clob(',"DEVICE_CODE_B_4_K_20_FDA_19":'));
        dbms_lob.append(l_json_request,
                        to_clob(l_temp_str));
    END IF;

   --------------------- Device Information Ends -----------------------


   ------------------- Annexure Information Starts ---------------------

   ------------------- Annexure E Starts ---------------------

    SELECT
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'CASE_ID' VALUE ce.case_id,
                'SEQ_NUM' VALUE ce.seq_num,
                'ANNEX_E' VALUE ce.imdrf_code
            RETURNING CLOB)
        RETURNING CLOB)
    INTO l_temp_str
    FROM
        case_event ce
    WHERE
        ce.case_id = l_case_id;

    IF l_temp_str IS NOT NULL THEN
        dbms_lob.append(l_json_request,
                        to_clob(',"ANNEX_E_INFO":'));
        dbms_lob.append(l_json_request,
                        to_clob(l_temp_str));
    END IF;

------------------- Annexure E Ends ---------------------

------------------- Annexure G Starts ---------------------
    SELECT
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'CASE_ID' VALUE cpc.case_id,
                'SEQ_NUM' VALUE cpc.seq_num,
                'PROD_SEQ_NUM' VALUE cpc.prod_seq_num,
                'ANNEX_G' VALUE cpc.imdrf_code
            RETURNING CLOB)
        RETURNING CLOB)
    INTO l_temp_str
    FROM
        case_prod_component cpc
    WHERE
        cpc.case_id = l_case_id;

    IF l_temp_str IS NOT NULL THEN
        dbms_lob.append(l_json_request,
                        to_clob(',"ANNEX_G_INFO":'));
        dbms_lob.append(l_json_request,
                        to_clob(l_temp_str));
    END IF;

------------------- Annexure G Ends ---------------------


------------------- Annexure F Starts ---------------------
    SELECT
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'CASE_ID' VALUE cphi.case_id,
                'SEQ_NUM' VALUE cphi.seq_num,
                'PROD_SEQ_NUM' VALUE cphi.prod_seq_num,
                'ANNEX_F' VALUE cphi.imdrf_code
            RETURNING CLOB)
        RETURNING CLOB)
    INTO l_temp_str
    FROM
        case_prod_health_impact cphi
    WHERE
        cphi.case_id = l_case_id;

    IF l_temp_str IS NOT NULL THEN
        dbms_lob.append(l_json_request,
                        to_clob(',"ANNEX_F_INFO":'));
        dbms_lob.append(l_json_request,
                        to_clob(l_temp_str));
    END IF;

------------------- Annexure F Ends ---------------------


------------------- Annexure B, C and D Starts ---------------------
    SELECT
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'CASE_ID' VALUE cpde.case_id,
                'SEQ_NUM' VALUE cpde.seq_num,
                'PROD_SEQ_NUM' VALUE cpde.prod_seq_num,
                'ANNEX_B' VALUE cpde.meth_imdrf,
                'ANNEX_C' VALUE cpde.res_imdrf,
                        'ANNEX_D' VALUE cpde.conc_imdrf
            RETURNING CLOB)
        RETURNING CLOB)
    INTO l_temp_str
    FROM
        case_prod_dev_eval cpde
    WHERE
        cpde.case_id = l_case_id;

    IF l_temp_str IS NOT NULL THEN
        dbms_lob.append(l_json_request,
                        to_clob(',"ANNEX_B_C_D_INFO":'));
        dbms_lob.append(l_json_request,
                        to_clob(l_temp_str));
    END IF;

------------------- Annexure B, C and D Ends ---------------------

------------------- Annexure A Starts ---------------------
    SELECT
        JSON_ARRAYAGG(
            JSON_OBJECT(
                'CASE_ID' VALUE cpdp.case_id,
                'SEQ_NUM' VALUE cpdp.seq_num,
                'PROD_SEQ_NUM' VALUE cpdp.prod_seq_num,
                'ANNEX_A' VALUE cpdp.imdrf_dev_cd
            RETURNING CLOB)
        RETURNING CLOB)
    INTO l_temp_str
    FROM
        case_prod_dev_patdev cpdp
    WHERE
        cpdp.case_id = l_case_id;

    IF l_temp_str IS NOT NULL THEN
        dbms_lob.append(l_json_request,
                        to_clob(',"ANNEX_A_INFO":'));
        dbms_lob.append(l_json_request,
                        to_clob(l_temp_str));
    END IF;

------------------- Annexure A Ends ---------------------

------------------- Annexure Information Ends ---------------------


   --------------------- Case classifications and references
    BEGIN
        SELECT
            JSON_ARRAYAGG(
                JSON_OBJECT(
                    'CASE_ID' VALUE l_case_id,
                    'CONTEXT' VALUE lc.context,
                    'KEYWORD' VALUE lc.keyword
                )
            RETURNING VARCHAR2(32000))
        INTO l_temp_str
        FROM
            (
                SELECT
                    description      keyword,
                    'CLASSIFICATION' context
                FROM
                         case_classifications c
                    JOIN lm_case_classification lc ON lc.classification_id = c.classification_id
                WHERE
                        c.case_id = l_case_id
                    AND c.deleted IS NULL
                UNION
                SELECT
                    decode(susar, 1, 'SUSAR', 0, 'NON-SUSAR',
                           'N/A')    keyword,
                    'CLASSIFICATION' context
                FROM
                    case_master
                WHERE
                    case_id = l_case_id
                UNION
                SELECT
                    c.ref_no keyword,
                    (
                        SELECT
                            t.type_desc
                        FROM
                            lm_ref_types t
                        WHERE
                            t.ref_type_id = c.ref_type_id
                    )        context
                FROM
                    case_reference c
                WHERE
                        c.case_id = l_case_id
                    AND c.deleted IS NULL
            ) lc
        WHERE
            lc.context NOT IN ( 'PREGNANT' ) /* Exclude hardcoded pregnancy */;

        IF l_temp_str IS NOT NULL THEN
            l_json_request := l_json_request
                              || ',"KEYWORDS":'
                              || l_temp_str;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                     || 'KEYWORDS Custom section - while generating JSON data for case: '
                     || p_case_num
                     || '  '
                     || substr(sqlerrm, 1, 1000) );
    END;
   /**************************************************************************************************************/

    -- Close the JSON outpout with '}'
    dbms_lob.append(l_json_request,
                    to_clob('}'));
    RETURN ( l_json_request );
EXCEPTION
    WHEN OTHERS THEN
        RETURN ( 'ERROR: HALO_ICSR_R3_GENERATE_ARGUS_DATA: '
                 || ' While generating JSON data for case: '
                 || p_case_num
                 || '  '
                 || substr(sqlerrm, 1, 1000) );
END;
/


create or replace FUNCTION HALO_API_CALL (
    pi_json_request   CLOB,
    pi_webservice_url VARCHAR2,
    pi_wallet_path    VARCHAR2
) RETURN CLOB IS
/******************************************************************************************************
-- Purpose              : API Calling based on HALOPV Version
-- Input                : Multiple
-- Changes              : Created, Priyadarshan Kumar, 09-Aug-2024
******************************************************************************************************/


    l_json_request     CLOB := pi_json_request;           -- JSON request data
    l_json_response    CLOB;           -- JSON response data
    errorstring        VARCHAR2(2000); -- Error message
    webservice_url     VARCHAR2(200) := pi_webservice_url;   -- Web service URL
    v_wallet_path      VARCHAR2(200) := pi_wallet_path;   -- Wallet path
    l_authorization    VARCHAR2(200);   -- Authorization token
    v_entity_name      VARCHAR2(30) := 'HALO_ICSR_R3_DATA_TRANSFER';  -- Entity name for logging

-- Added new parameters for New Authentication

    v_current_date     VARCHAR2(50 CHAR) := to_char(current_timestamp, 'DD-MON-YYYY HH24:MI:SS');
    v_auth_timestamp   VARCHAR2(50 CHAR);
    v_auth_hash_key    VARCHAR2(2000);
    v_auth_tenant_id   NUMBER;
    v_auth_secret_key  NUMBER;
    v_current_utc_time VARCHAR2(100);
    v_halo_version     NUMBER;
BEGIN
    l_json_response := NULL;

-- Retrieve all necessary values based on HALO Version in order to start API Call

-- Fetch HALO Version from HALO_CONFIG table

    BEGIN
        SELECT
            value
        INTO v_halo_version
        FROM
            halo_config
        WHERE
            parameter = 'HALO_VERSION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_VERSION: '
                                                   || 'Parameter for HALO_VERSION is not configured in halo_config'
                                                   || sqlerrm);
            RETURN l_json_response;
    END;

if v_halo_version >  4.9 then

    BEGIN
        SELECT
            value
        INTO v_auth_timestamp
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TIMESTAMP';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                   || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'
                                                   || sqlerrm);
            RETURN l_json_response;
    END;

    BEGIN
        SELECT
            value
        INTO v_auth_hash_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_HASH_KEY';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                   || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'
                                                   || sqlerrm);
            RETURN l_json_response;
    END;

    BEGIN
        SELECT
            value
        INTO v_auth_tenant_id
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TENANT_ID';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                   || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'
                                                   || sqlerrm);
            RETURN l_json_response;
    END;

    BEGIN
        SELECT
            value
        INTO v_auth_secret_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_SECRET_KEY';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                   || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'
                                                   || sqlerrm);
            RETURN l_json_response;
    END;

    SELECT
        to_char(TO_TIMESTAMP_TZ(to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
                'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS')
    INTO v_current_utc_time
    FROM
        dual;



  --  select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
   -- into v_current_utc_time
   -- from dual;

    IF (
        v_auth_hash_key IS NULL
        AND v_auth_timestamp IS NULL
    ) THEN


    -- Debugging call --

        halo_write_log('DEBUGGING', 'INFO', 'v_auth_timestamp IF ELSE: ' || v_auth_timestamp, NULL, NULL,
                      l_json_request);
        UPDATE halo_config
        SET
            value = v_current_utc_time
        WHERE
            parameter = 'AUTH_TIMESTAMP';

        UPDATE halo_config
        SET
            value = (
                SELECT
                    sys.dbms_crypto.hash(utl_raw.cast_to_raw('TEN'
                                                             || v_auth_tenant_id
                                                             || ';'
                                                             || v_current_utc_time
                                                             || ';'
                                                             || v_auth_secret_key),
                                         4)
                FROM
                    dual
            )
        WHERE
            parameter = 'AUTH_HASH_KEY';

    ELSIF (
        v_auth_hash_key IS NOT NULL
        AND v_auth_timestamp IS NOT NULL
    ) THEN
            if(((TO_DATE(v_auth_timestamp,'YYYY-MM-DD"T"HH24:MI:SS')) != TO_DATE(v_current_utc_time,'YYYY-MM-DD"T"HH24:MI:SS')) OR
            (TO_NUMBER(TO_CHAR(TO_DATE(v_auth_timestamp,'YYYY-MM-DD"T"HH24:MI:SS'),'HH24')))< (TO_NUMBER(TO_CHAR(TO_DATE(v_current_utc_time,'YYYY-MM-DD"T"HH24:MI:SS'),'HH24')))
            )                                                                                                                                            THEN

-- Debugging
            halo_write_log('DEBUGGING', 'INFO', 'v_auth_timestamp ELSIF: ' || v_auth_timestamp, NULL, NULL,
                          l_json_request);
            UPDATE halo_config
            SET
                value = v_current_utc_time
            WHERE
                parameter = 'AUTH_TIMESTAMP';

            UPDATE halo_config
            SET
                value = (
                    SELECT
                        sys.dbms_crypto.hash(utl_raw.cast_to_raw('TEN'
                                                                 || v_auth_tenant_id
                                                                 || ';'
                                                                 || v_current_utc_time
                                                                 || ';'
                                                                 || v_auth_secret_key),
                                             4)
                    FROM
                        dual
                )
            WHERE
                parameter = 'AUTH_HASH_KEY';

        END IF;
    END IF;

-- Get the timestamp

    SELECT
        value
    INTO v_auth_timestamp
    FROM
        halo_config
    WHERE
        parameter = 'AUTH_TIMESTAMP';

-- Get the HASH Key

    SELECT
        value
    INTO v_auth_hash_key
    FROM
        halo_config
    WHERE
        parameter = 'AUTH_HASH_KEY';

    SELECT
        value
    INTO v_auth_tenant_id
    FROM
        halo_config
    WHERE
        parameter = 'AUTH_TENANT_ID';

end if;

-- Get the secret key
    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'Parameter for api key is not configured in HALO_CONFIG');
            RETURN l_json_response;
    END;


-- Calling APIs based on the HALO Version

        IF v_halo_version >  4.9 THEN

        apex_web_service.g_request_headers.DELETE;
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/json';
        apex_web_service.g_request_headers(2).name := 'Authorization';
        apex_web_service.g_request_headers(2).value := l_authorization;

--  New authentication code starts here

        apex_web_service.g_request_headers(3).name := 'Tenant_ID';
        apex_web_service.g_request_headers(3).value := v_auth_tenant_id;
        apex_web_service.g_request_headers(4).name := 'Auth_Hash';
        apex_web_service.g_request_headers(4).value := v_auth_hash_key;
        apex_web_service.g_request_headers(5).name := 'Auth_Timestamp';
        apex_web_service.g_request_headers(5).value := v_auth_timestamp;

-- New authentication code ends here

        l_json_response := apex_web_service.make_rest_request(p_url => webservice_url, p_wallet_path => v_wallet_path, p_http_method => 'POST'

        , p_body => l_json_request);

        END IF;

        IF v_halo_version < 5 THEN

        apex_web_service.g_request_headers.DELETE;
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/json';
        apex_web_service.g_request_headers(2).name := 'Authorization';
        apex_web_service.g_request_headers(2).value := l_authorization;
        l_json_response := apex_web_service.make_rest_request(p_url => webservice_url, p_wallet_path => v_wallet_path, p_http_method => 'POST'
        , p_body => l_json_request);

        END IF;

    RETURN l_json_response;
EXCEPTION
    WHEN OTHERS THEN
        -- Log Error
        halo_write_log('HALO_API_CALL', 'ERROR', 'HALO_API_CALL'
                                                 || 'Could not call the API: '
                                                 || sqlerrm
                                                 || chr(13)
                                                 || chr(10)
                                                 || dbms_utility.format_error_backtrace());

        RETURN l_json_response;
END halo_api_call;
/

--------------------------------------------------------------
-- HALO_ICSR_R3_DATA_TRANSFER
--------------------------------------------------------------
create or replace PROCEDURE HALO_ICSR_R3_DATA_TRANSFER (
    p_case_num   VARCHAR2,          -- Input: Argus Case number
    p_state_id   NUMBER,            -- Input: State ID
    p_out_status OUT NUMBER         -- Output: JSON response status
) AS
/******************************************************************************************************
--  File Name            : A03_HALO_ICSR_R3_DATA_TRANSFER.sql
--  Purpose              : Transfers Argus single case data to APEX Restful service in the form of
                            JSON generated by HALO_ICSR_R3_GENERATE_ARGUS_DATA()
--  Input                : p_case_num (Argus Case number)
--  Created by           : Kranthi Kishore 22-MAY-2020 - V1
--  Modified By          : Kanthi Kishore 06-Jun-2020 - V2
                           added halo_write_error_log (substr(l_json_response,1,1000));
                           Peter Stroyer Pallesen 23-Jun-2020 v3
                           Added State_ID as a call parameter

                           Peter Stroyer Pallesen 30-12-2020 v4 (CSSERVICE-134520)
                           Added email error notification

                         V3  : DD 12-10-2023
                           Modified to add p_out_status variable to handle JSON response. CSL error.
                         V4  : DD 08-MAR-2024 ARG-18
                         V5 : AG 22-APR-2025 ARG-59,ARG-82
******************************************************************************************************/
    l_json_request     CLOB;           -- JSON request data
    l_json_response    CLOB;           -- JSON response data
    errorstring        VARCHAR2(2000); -- Error message
    webservice_url     VARCHAR2(200);   -- Web service URL
    v_wallet_path      VARCHAR2(200);   -- Wallet path
    l_authorization    VARCHAR2(200);   -- Authorization token
    v_entity_name      VARCHAR2(30) := 'HALO_ICSR_R3_DATA_TRANSFER';  -- Entity name for logging

-- Added new parameters for New Authentication

    v_current_date     VARCHAR2(50 CHAR) := to_char(current_timestamp, 'DD-MON-YYYY HH24:MI:SS');
    v_auth_timestamp   VARCHAR2(50 CHAR);
    v_auth_hash_key    VARCHAR2(2000);
    v_auth_tenant_id   NUMBER;
    v_auth_secret_key  NUMBER;
    v_current_utc_time VARCHAR2(100);
    v_halo_version     NUMBER;
BEGIN

-- New authentication code starts from here


    halo_write_log(v_entity_name, 'DEBUG', 'HALO_ICSR_R3_DATA_TRANSFER: ENTRY');


    BEGIN
        SELECT
            value
        INTO v_halo_version
        FROM
            halo_config
        WHERE
            parameter = 'HALO_VERSION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_VERSION: '
                                                   || 'Parameter for HALO_VERSION is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;


    BEGIN
        SELECT
            value
        INTO v_auth_timestamp
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TIMESTAMP';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                   || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_auth_hash_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_HASH_KEY';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                   || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_auth_tenant_id
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TENANT_ID';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                   || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_auth_secret_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_SECRET_KEY';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                   || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;

    SELECT
        to_char(TO_TIMESTAMP_TZ(to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
                'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS')
    INTO v_current_utc_time
    FROM
        dual;



  --  select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
   -- into v_current_utc_time
   -- from dual;

    IF (
        v_auth_hash_key IS NULL
        AND v_auth_timestamp IS NULL
    ) THEN


    -- Debugging call --

halo_write_log('DEBUGGING', 'INFO', 'v_auth_timestamp IF ELSE: ' || v_auth_timestamp, NULL, NULL,
                  l_json_request);


        UPDATE halo_config
        SET
            value = v_current_utc_time
        WHERE
            parameter = 'AUTH_TIMESTAMP';

        UPDATE halo_config
        SET
            value = (
                SELECT
                    sys.dbms_crypto.hash(utl_raw.cast_to_raw('TEN'
                                                             || v_auth_tenant_id
                                                             || ';'
                                                             || v_current_utc_time
                                                             || ';'
                                                             || v_auth_secret_key),
                                         4)
                FROM
                    dual
            )
        WHERE
            parameter = 'AUTH_HASH_KEY';

        elsif(v_auth_hash_key is not null and v_auth_timestamp is not null)
        then
            if(((TO_DATE(v_auth_timestamp,'YYYY-MM-DD"T"HH24:MI:SS')) != TO_DATE(v_current_utc_time,'YYYY-MM-DD"T"HH24:MI:SS')) OR
            (TO_NUMBER(TO_CHAR(TO_DATE(v_auth_timestamp,'YYYY-MM-DD"T"HH24:MI:SS'),'HH24')))< (TO_NUMBER(TO_CHAR(TO_DATE(v_current_utc_time,'YYYY-MM-DD"T"HH24:MI:SS'),'HH24')))
            )
            THEN

            -- Debugging
            halo_write_log('DEBUGGING', 'INFO', 'v_auth_timestamp ELSIF: ' || v_auth_timestamp, NULL, NULL,
                  l_json_request);


                    update halo_config
                    set value =v_current_utc_time
                    where PARAMETER = 'AUTH_TIMESTAMP';


                    update halo_config
                    set value =(SELECT sys.dbms_crypto.hash(utl_raw.cast_to_raw('TEN'
                                                             || v_auth_tenant_id
                                                             || ';'
                                                             || v_current_utc_time
                                                             || ';'
                                                             || v_auth_secret_key),
                                         4) FROM DUAL)
                    where parameter='AUTH_HASH_KEY';


            end if;


    END IF;

    SELECT
        value
    INTO v_auth_timestamp
    FROM
        halo_config
    WHERE
        parameter = 'AUTH_TIMESTAMP';

    SELECT
        value
    INTO v_auth_hash_key
    FROM
        halo_config
    WHERE
        parameter = 'AUTH_HASH_KEY';

    SELECT
        value
    INTO v_auth_tenant_id
    FROM
        halo_config
    WHERE
        parameter = 'AUTH_TENANT_ID';



-- New authentication code ends here



-- Get the webservice URL
    BEGIN
        SELECT
            value
        INTO webservice_url
        FROM
            halo_config
        WHERE
            parameter = 'ARGUS_ICSR_R3_WEBSERVICE';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'Parameter for webservice URL is not configured in HALO_CONFIG');
            RETURN;
    END;

    -- Get the wallet path

    BEGIN
        SELECT
            value
        INTO v_wallet_path
        FROM
            halo_config
        WHERE
            parameter = 'WALLET_PATH';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'Parameter for Wallet PATH is not configured in HALO_CONFIG');
            RETURN;
    END;

-- Get the secret key
    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'Parameter for api key is not configured in HALO_CONFIG');
            RETURN;
    END;

-- Get the R3 json data


    SELECT
        halo_icsr_r3_generate_argus_data(p_case_num, p_state_id)
    INTO l_json_request
    FROM
        dual;



-- statement to capture Request JSON

    halo_write_log(v_entity_name, 'INFO', 'Case: ' || p_case_num, NULL, NULL,
                  l_json_request);

    -- In case of json error, log the errror and return
    IF substr(l_json_request, 1, 5) = 'ERROR' THEN
        halo_write_log(v_entity_name, 'ERROR', 'Case: ' || p_case_num, NULL, NULL,
                      l_json_request);
        p_out_status := 0;
    -- Notify support mailbox of error
        BEGIN
            halo_error_mail(p_from => 'support@insife.cloud', p_to => 'support@insife.com', p_sub => 'Automatic error notification (case: '
                                                                                                     || p_case_num
                                                                                                     || ')', p_body => 'This email is triggered due to an error in forming json for Argus-HALO integration for '
                                                                                                                       || webservice_url
                                                                                                                       || '. Please refer to the following error message: '
                                                                                                                       || l_json_request
                                                                                                                       || '. '
                                                                                                                       || sqlerrm, p_port => 587
                                                                                                                       );
       -- If email error handling fails, we cannot do anything (email notif. is last step in error handling)
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;

        RETURN;
    END IF;

-- New authentication code

    l_json_response := empty_clob();

-- Debugging call --

halo_write_log('DEBUGGING', 'INFO', 'l_authorization: ' || l_authorization ||'v_auth_tenant_id:'|| v_auth_tenant_id ||'v_auth_hash_key:'||v_auth_hash_key ||'v_auth_timestamp:' || v_auth_timestamp, NULL, NULL,
                  l_json_request);

 -- make the webservice call if  JSON is formed.




    BEGIN
    l_json_response:= halo_api_call (l_json_request,webservice_url,v_wallet_path);
--    if v_halo_version = 5 then
--        apex_web_service.g_request_headers.DELETE;
--        apex_web_service.g_request_headers(1).name := 'Content-Type';
--        apex_web_service.g_request_headers(1).value := 'application/json';
--        apex_web_service.g_request_headers(2).name := 'Authorization';
--        apex_web_service.g_request_headers(2).value := l_authorization;
--
----  New authentication code starts here
--
--        apex_web_service.g_request_headers(3).name := 'Tenant_ID';
--        apex_web_service.g_request_headers(3).value := v_auth_tenant_id;
--        apex_web_service.g_request_headers(4).name := 'Auth_Hash';
--        apex_web_service.g_request_headers(4).value := v_auth_hash_key;
--        apex_web_service.g_request_headers(5).name := 'Auth_Timestamp';
--        apex_web_service.g_request_headers(5).value := v_auth_timestamp;
--
---- New authentication code ends here
--
--        l_json_response := apex_web_service.make_rest_request(p_url => webservice_url, p_wallet_path => v_wallet_path, p_http_method => 'POST'
--
--        , p_body => l_json_request);
--
--end if;
--
--
--    if v_halo_version < 5 then
--        apex_web_service.g_request_headers.DELETE;
--        apex_web_service.g_request_headers(1).name := 'Content-Type';
--        apex_web_service.g_request_headers(1).value := 'application/json';
--        apex_web_service.g_request_headers(2).name := 'Authorization';
--        apex_web_service.g_request_headers(2).value := l_authorization;
--
--        l_json_response := apex_web_service.make_rest_request(p_url => webservice_url, p_wallet_path => v_wallet_path, p_http_method => 'POST'
--
--        , p_body => l_json_request);
--
--end if;



-- statement to capture Response JSON

        halo_write_log(v_entity_name, 'INFO', 'Case: ' || p_case_num, NULL, NULL,
                      nvl(l_json_response,'No Response'));
        IF apex_web_service.g_status_code IN ( 200, 202 ) THEN
            halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_ICSR_DATA: Case Trasnfer Started ' || p_case_num, NULL, NULL,
                          substr(l_json_request, 1, 4000), substr(l_json_response, 1, 4000));

            p_out_status := 1;
            RETURN;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            p_out_status := 0;
            halo_write_log(v_entity_name, 'DEBUG', 'Case: '
                                                   || p_case_num
                                                   || '.', NULL, NULL,
                          l_json_request, l_json_response);

            halo_write_log(v_entity_name, 'INFO', 'Case: '
                                                  || p_case_num
                                                  || '.');


            halo_error_mail(p_from => 'support@insife.cloud', p_to => 'support@insife.com', p_sub => 'Automatic error notification (case: '
                                                                                                     || p_case_num
                                                                                                     || ')', p_body => 'This email is triggered due to an error in calling API for Argus-HALO integration for'
                                                                                                                       || webservice_url
                                                                                                                       || '. Please refer to the following error message: '
                                                                                                                       || l_json_request
                                                                                                                       || '. '
                                                                                                                       || l_json_response, p_port => 587
                                                                                                                       );


            RETURN;
    END;

-- Get web service call status
    IF apex_web_service.g_status_code NOT IN ( 200, 202 ) THEN
        halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_ICSR_DATA: Error (http error '
                                               || apex_web_service.g_status_code
                                               || ' in .', NULL, NULL,
                      substr(l_json_request, 1, 4000), substr(l_json_response, 1, 4000));

         halo_error_mail(p_from => 'support@insife.cloud', p_to => 'support@insife.com', p_sub => 'Automatic error notification (case: '
                                                                                                     || p_case_num
                                                                                                     || ')', p_body => 'This email is triggered due to an error in API calling webservice of Argus-HALO integration for '
                                                                                                                       || webservice_url
                                                                                                                       || '. Please refer to the following error message: '
                                                                                                                       || l_json_request
                                                                                                                       || '. '
                                                                                                                       || sqlerrm, p_port => 587
                                                                                                                       );

        p_out_status := 0;
        RETURN;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        errorstring := 'ERROR: HALO_ICSR_R3_DATA_TRANSFER: An unexpected error occured while transferring Argus ICSR data to HALO.'
                       || '   JSON Request :'
                       || substr(l_json_request, 1, 300)
                       || '   '
                       || substr(sqlerrm, 1, 1000);

        halo_write_log(v_entity_name, 'ERROR', errorstring);
        p_out_status := 0;

        halo_error_mail(p_from => 'support@insife.cloud', p_to => 'support@insife.com', p_sub => 'Automatic error notification (case: '
                                                                                                     || p_case_num
                                                                                                     || ')', p_body => 'This email is triggered due to an error in procedure halo_icsr_r3_data_transfer '
                                                                                                                       || webservice_url
                                                                                                                       || '. Please refer to the following error message: '
                                                                                                                       || l_json_request
                                                                                                                       || '. '
                                                                                                                       || sqlerrm, p_port => 587
                                                                                                                       );
END HALO_ICSR_R3_DATA_TRANSFER;
/



--------------------------------------------------------------
-- HALO_TRANSFER_ADMIN_ROUTES_CONFIG
--------------------------------------------------------------

CREATE OR REPLACE PROCEDURE HALO_TRANSFER_ADMIN_ROUTES_CONFIG (
    is_initial NUMBER DEFAULT 0
) AS

/******************************************************************************************************
--  Purpose              : Transfer route of admin data from Argus to the HALO configuration API
--  Input                : N/A (all route of admins are transferred)
--  Changes:             : Created, Praveen Gupta, 08-Jul-2022
******************************************************************************************************/
    l_json_request     CLOB;
    l_json_response    CLOB;
    errorstring        CLOB;
    webservice_url     VARCHAR2(200);
    l_sender           VARCHAR2(200);
    l_receiver         VARCHAR2(200);
    l_authorization    VARCHAR2(200);
    l_halo_code_source VARCHAR2(200);
    v_current_date     DATE := to_char(current_timestamp, 'DD-MON-YYYY HH24:MI:SS');
    v_last_run         DATE;
    v_wallet_path      VARCHAR2(200);
    v_entity_name      VARCHAR2(100) := 'ADMIN_ROUTES';
    v_halo_char_id     VARCHAR2(200) := NULL;
    v_operation_type   VARCHAR(1) := '1';


    -- Added new parameters for New Authentication

    v_auth_timestamp   VARCHAR2(50 CHAR);
    v_auth_hash_key    VARCHAR2(2000);
    v_auth_tenant_id   NUMBER;
    v_auth_secret_key  NUMBER;
    v_current_utc_time VARCHAR2(100);
    v_halo_version     NUMBER;
BEGIN
    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: ENTRY');
    BEGIN
        SELECT
            value
        INTO webservice_url
        FROM
            halo_config
        WHERE
            parameter = 'HALO_PRODUCT_CONFIG_WEBSERVICE';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: '
                                                   || 'Parameter for webservice URL is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;


    -- Added code to fetch HALO version

    BEGIN
        SELECT
            value
        INTO v_halo_version
        FROM
            halo_config
        WHERE
            parameter = 'HALO_VERSION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_VERSION: '
                                                   || 'Parameter for HALO_VERSION is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;


    -- New authentication code starts from here


    IF v_halo_version >= 5 THEN


-- Get the secret key
        BEGIN
            SELECT
                value
            INTO l_authorization
            FROM
                halo_config
            WHERE
                parameter = 'HALO_AUTHORIZATION';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'Parameter for api key is not configured in HALO_CONFIG');
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_timestamp
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TIMESTAMP';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_hash_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_HASH_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_tenant_id
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TENANT_ID';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_secret_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_SECRET_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        SELECT
            to_char(TO_TIMESTAMP_TZ(to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
                    'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS')
        INTO v_current_utc_time
        FROM
            dual;



  --  select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
   -- into v_current_utc_time
   -- from dual;

        IF (
            v_auth_hash_key IS NULL
            AND v_auth_timestamp IS NULL
        ) THEN
            UPDATE halo_config
            SET
                value = v_current_utc_time
            WHERE
                parameter = 'AUTH_TIMESTAMP';

            UPDATE halo_config
            SET
                value = (
                    SELECT
                        sys.dbms_crypto.hash(
                            utl_raw.cast_to_raw('TEN'
                                                || v_auth_tenant_id
                                                || ';'
                                                || v_current_utc_time
                                                || ';'
                                                || v_auth_secret_key),
                            4
                        )
                    FROM
                        dual
                )
            WHERE
                parameter = 'AUTH_HASH_KEY';

        ELSIF (
            v_auth_hash_key IS NOT NULL
            AND v_auth_timestamp IS NOT NULL
        ) THEN
            IF ( ( ( TO_DATE ( v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS' ) ) != TO_DATE ( v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'
            ) )
            OR ( TO_NUMBER ( to_char(TO_DATE(v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) < ( TO_NUMBER ( to_char(TO_DATE
            (v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) ) THEN
                UPDATE halo_config
                SET
                    value = v_current_utc_time
                WHERE
                    parameter = 'AUTH_TIMESTAMP';

                UPDATE halo_config
                SET
                    value = (
                        SELECT
                            sys.dbms_crypto.hash(
                                utl_raw.cast_to_raw('TEN'
                                                    || v_auth_tenant_id
                                                    || ';'
                                                    || v_current_utc_time
                                                    || ';'
                                                    || v_auth_secret_key),
                                4
                            )
                        FROM
                            dual
                    )
                WHERE
                    parameter = 'AUTH_HASH_KEY';

            END IF;
        END IF;

        SELECT
            value
        INTO v_auth_timestamp
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TIMESTAMP';

        SELECT
            value
        INTO v_auth_hash_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_HASH_KEY';

        SELECT
            value
        INTO v_auth_tenant_id
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TENANT_ID';

    END IF;

-- New authentication code ends here



    BEGIN
        SELECT
            CAST(from_tz(CAST(sysdate AS TIMESTAMP),(
                SELECT
                    value
                FROM
                    cmn_profile
                WHERE
                        key = 'DATABASE_TIMEZONE'
                    AND section = 'SYSTEM'
            )) AT TIME ZONE 'GMT' AS DATE)
        INTO v_current_date
        FROM
            dual;

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Unable to convert sysdate to GMT'
                                                   || sqlerrm);
		--halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for webservice URL is not configured in HALO_CONFIG'||sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_wallet_path
        FROM
            halo_config
        WHERE
            parameter = 'WALLET_PATH';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: '
                                                   || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: '
                                                   || 'Parameter for api key is not configured in HALO_CONFIG'
                                                   || sqlerrm);
    END;

    BEGIN
        SELECT
            value
        INTO l_sender
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_SENDER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: '
                                                   || 'Parameter for sender mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_receiver
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_RECEIVER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: '
                                                   || 'Parameter for receiver mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            halo_char_id
        INTO l_halo_code_source
        FROM
            stg_argus_halo_idmap
        WHERE
            entity_name = 'SOURCES';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: '
                                                   || 'Parameter for HALO_CHAR_ID is not configured in STG_ARGUS_HALO_IDMAP'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            TO_DATE(value, 'DD-MM-YYYY HH24:MI:SS')
        INTO v_last_run
        FROM
            halo_config
        WHERE
            parameter = 'ADMIN_ROUTES_LAST_RUN';

    EXCEPTION
        WHEN OTHERS THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: '
                                                   || 'Parameter for ADMIN_ROUTES_LAST_RUN is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: VALIDATION COMPLETE');

	--Prepare JSON for all route of admin in database
    FOR curadmrot IN (
        SELECT
            admin_route_id
        FROM
            lm_admin_route
        WHERE
            ( last_update_time >= v_last_run
              AND last_update_time <= v_current_date
              AND 1 != is_initial )
            OR ( deleted IS NULL
                 AND 1 = is_initial )
        ORDER BY
            admin_route_id ASC
    ) LOOP
        v_halo_char_id := NULL;
        BEGIN
            SELECT
                halo_char_id
            INTO v_halo_char_id
            FROM
                stg_argus_halo_idmap
            WHERE
                    entity_name = v_entity_name
                AND argus_id = curadmrot.admin_route_id;

        EXCEPTION
            WHEN OTHERS THEN
                v_halo_char_id := NULL;
                halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: '
                                                      || 'IS_INITIAL: '
                                                      || is_initial
                                                      || '.  OPERATION_TYPE = 1 AND V_HALO_CHAR_ID IS NULL FOR ARGUS_ID:'
                                                      || curadmrot.admin_route_id);

        END;

        IF ( v_halo_char_id IS NOT NULL ) THEN
            v_operation_type := '2';
        ELSE
            v_operation_type := '1';
        END IF;

        SELECT
            JSON_OBJECT(
                'HALO_message' VALUE
                    JSON_OBJECT(
                        'MPD_entities' VALUE
                            JSON_OBJECT(
                                'ADMIN_ROUTE' VALUE JSON_ARRAYAGG(
                                    JSON_OBJECT(
                                        'HALO_CODE' VALUE nvl2(v_halo_char_id, v_halo_char_id, ''),
                                                'OPERATION_TYPE' VALUE decode(
                                            nvl2(lar.deleted, 'Y', 'N'),
                                            'N',
                                            v_operation_type,
                                            'Y',
                                            '5'
                                        ),
                                                'TERM_TYPE_CODE' VALUE 'STD',
                                                'ADMIN_ROUTE_NAME' VALUE lar.route,
                                                'COMMENT_PHARM_FORM' VALUE lar.route_desc,
                                                'DEPRECATED_FLAG' VALUE nvl2(lar.deleted, 'Y', 'N'),
                                                'SENDER_LOCAL_CODE' VALUE lar.admin_route_id,
                                                'HALO_CODE_SOURCE' VALUE l_halo_code_source
                                    RETURNING CLOB)
                                RETURNING CLOB)
                            RETURNING CLOB)
                    RETURNING CLOB)
            RETURNING CLOB)
        INTO l_json_request
        FROM
            lm_admin_route lar
        WHERE
            lar.admin_route_id = curadmrot.admin_route_id;

        BEGIN
            IF v_halo_version < 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;
            END IF;

            IF v_halo_version >= 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;

--  New authentication code starts here

                apex_web_service.g_request_headers(3).name := 'Tenant_ID';
                apex_web_service.g_request_headers(3).value := v_auth_tenant_id;
                apex_web_service.g_request_headers(4).name := 'Auth_Hash';
                apex_web_service.g_request_headers(4).value := v_auth_hash_key;
                apex_web_service.g_request_headers(5).name := 'Auth_Timestamp';
                apex_web_service.g_request_headers(5).value := v_auth_timestamp;

-- New authentication code ends here

            END IF;

            l_json_response := apex_web_service.make_rest_request(
                p_url         => webservice_url,
                p_http_method => 'POST',
                p_body        => l_json_request,
                p_wallet_path => v_wallet_path
            );

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: Error in loading ADMIN_ROUTES.', v_halo_char_id
                , curadmrot.admin_route_id,
                               l_json_request, l_json_response);

                RETURN;
        END;

        BEGIN
            IF ( v_operation_type = '1' ) THEN
                import_halo_code_admin_routes(l_json_response, v_entity_name);
                halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: Updated to halo successfully', v_halo_char_id
                , curadmrot.admin_route_id);
                halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: Response from HALO PRODUCTCONFIG endpoint'
                , v_halo_char_id, curadmrot.admin_route_id,
                               l_json_request, l_json_response);

            ELSE
                halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: NO UPDATE TO STG_ARGUS_HALO_IDMAP.', v_halo_char_id
                , curadmrot.admin_route_id,
                               l_json_request, l_json_response);
            END IF;
        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: Error while parsing halo response for halo and Argus ID mapping.'
                , v_halo_char_id, curadmrot.admin_route_id,
                               l_json_request, l_json_response);
        END;

    END LOOP;

    halo_update_config_values('ADMIN_ROUTES_LAST_RUN',
                              to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'));
    halo_write_log(v_entity_name,
                   'DEBUG',
                   'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: COMPLETED ADMIN_ROUTES. v_current_date' || to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'
                   ));
EXCEPTION
    WHEN OTHERS THEN
        errorstring := 'HALO_TRANSFER_ADMIN_ROUTES_CONFIG: An unexpected error occured while transferring Admin route data to HALO. '
                       || substr(sqlerrm, 1, 3000)
                       || '. '
                       || dbms_utility.format_error_backtrace();

        halo_write_log(v_entity_name, 'ERROR', errorstring, NULL, NULL,
                       l_json_request, l_json_response);
        --halo_write_error_log (errorstring);

        -- Notify support mailbox of error
        halo_error_mail(
            p_from => l_sender,
            p_to   => l_receiver,
            p_sub  => 'Automatic error notification for Argus-HALO medicinal Admin route configuration',
            p_body => 'This email is triggered due to an error in Argus-HALO integration for '
                      || webservice_url
                      || '. Please refer to the following error message: '
                      || l_json_request
                      || '. '
                      || sqlerrm,
            p_port => 587
        );

END HALO_TRANSFER_ADMIN_ROUTES_CONFIG;
/


--------------------------------------------------------------
-- HALO_TRANSFER_MED_PRODUCT_CONFIG
--------------------------------------------------------------

CREATE OR REPLACE PROCEDURE HALO_TRANSFER_MED_PRODUCT_CONFIG (
    is_initial NUMBER DEFAULT 0
) AS

/******************************************************************************************************
--  Purpose              : Transfer medicinal product data from Argus to the HALO configuration API
--  Input                : N/A (all products are transferred)
--  Changes:             : Created, Praveen Gupta, 19-Jul-2022
						 : Issue fixing Sudarshan Hegde, 14-Sep-2022 - HLP-2289
******************************************************************************************************/
    l_json_request     CLOB;
    l_json_response    CLOB;
    errorstring        VARCHAR2(2000);
    webservice_url     VARCHAR2(200);
    l_sender           VARCHAR2(200);
    l_receiver         VARCHAR2(200);
    m_mp_id            INTEGER;
    l_authorization    VARCHAR2(200);
    l_halo_code_source VARCHAR2(200);
    v_current_date     DATE := to_char(current_timestamp, 'DD-MON-YYYY HH24:MI:SS');
    v_last_run         DATE;
    v_wallet_path      VARCHAR2(200);
    v_entity_name      VARCHAR2(100) := 'PRODUCT';
    v_halo_char_id     VARCHAR2(200) := NULL;
    v_operation_type   VARCHAR(1) := '1';


  -- Added new parameters for New Authentication

    v_auth_timestamp   VARCHAR2(50 CHAR);
    v_auth_hash_key    VARCHAR2(2000);
    v_auth_tenant_id   NUMBER;
    v_auth_secret_key  NUMBER;
    v_current_utc_time VARCHAR2(100);
    v_halo_version     NUMBER;
BEGIN
    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: ENTRY');
    BEGIN
        SELECT
            value
        INTO webservice_url
        FROM
            halo_config
        WHERE
            parameter = 'HALO_PRODUCT_CONFIG_WEBSERVICE';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Parameter for webservice URL is not configured in HALO_CONFIG'
                                                   || sqlerrm);
		--halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for webservice URL is not configured in HALO_CONFIG'||sqlerrm);
            RETURN;
    END;


    -- Added code to fetch HALO version

    BEGIN
        SELECT
            value
        INTO v_halo_version
        FROM
            halo_config
        WHERE
            parameter = 'HALO_VERSION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_VERSION: '
                                                   || 'Parameter for HALO_VERSION is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;



-- New authentication code starts from here


    IF v_halo_version = 5 THEN


-- Get the secret key
        BEGIN
            SELECT
                value
            INTO l_authorization
            FROM
                halo_config
            WHERE
                parameter = 'HALO_AUTHORIZATION';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'Parameter for api key is not configured in HALO_CONFIG');
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_timestamp
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TIMESTAMP';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_hash_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_HASH_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_tenant_id
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TENANT_ID';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_secret_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_SECRET_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        SELECT
            to_char(TO_TIMESTAMP_TZ(to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
                    'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS')
        INTO v_current_utc_time
        FROM
            dual;



  --  select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
   -- into v_current_utc_time
   -- from dual;

        IF (
            v_auth_hash_key IS NULL
            AND v_auth_timestamp IS NULL
        ) THEN
            UPDATE halo_config
            SET
                value = v_current_utc_time
            WHERE
                parameter = 'AUTH_TIMESTAMP';

            UPDATE halo_config
            SET
                value = (
                    SELECT
                        sys.dbms_crypto.hash(
                            utl_raw.cast_to_raw('TEN'
                                                || v_auth_tenant_id
                                                || ';'
                                                || v_current_utc_time
                                                || ';'
                                                || v_auth_secret_key),
                            4
                        )
                    FROM
                        dual
                )
            WHERE
                parameter = 'AUTH_HASH_KEY';

        ELSIF (
            v_auth_hash_key IS NOT NULL
            AND v_auth_timestamp IS NOT NULL
        ) THEN
            IF ( ( ( TO_DATE ( v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS' ) ) != TO_DATE ( v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'
            ) )
            OR ( TO_NUMBER ( to_char(TO_DATE(v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) < ( TO_NUMBER ( to_char(TO_DATE
            (v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) ) THEN
                UPDATE halo_config
                SET
                    value = v_current_utc_time
                WHERE
                    parameter = 'AUTH_TIMESTAMP';

                UPDATE halo_config
                SET
                    value = (
                        SELECT
                            sys.dbms_crypto.hash(
                                utl_raw.cast_to_raw('TEN'
                                                    || v_auth_tenant_id
                                                    || ';'
                                                    || v_current_utc_time
                                                    || ';'
                                                    || v_auth_secret_key),
                                4
                            )
                        FROM
                            dual
                    )
                WHERE
                    parameter = 'AUTH_HASH_KEY';

            END IF;
        END IF;

        SELECT
            value
        INTO v_auth_timestamp
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TIMESTAMP';

        SELECT
            value
        INTO v_auth_hash_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_HASH_KEY';

        SELECT
            value
        INTO v_auth_tenant_id
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TENANT_ID';

    END IF;

-- New authentication code ends here




    BEGIN
        SELECT
            CAST(from_tz(CAST(sysdate AS TIMESTAMP),(
                SELECT
                    value
                FROM
                    cmn_profile
                WHERE
                        key = 'DATABASE_TIMEZONE'
                    AND section = 'SYSTEM'
            )) AT TIME ZONE 'GMT' AS DATE)
        INTO v_current_date
        FROM
            dual;

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Unable to convert sysdate to GMT'
                                                   || sqlerrm);
		--halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for webservice URL is not configured in HALO_CONFIG'||sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            CAST(from_tz(CAST(sysdate AS TIMESTAMP),(
                SELECT
                    value
                FROM
                    cmn_profile
                WHERE
                        key = 'DATABASE_TIMEZONE'
                    AND section = 'SYSTEM'
            )) AT TIME ZONE 'GMT' AS DATE)
        INTO v_current_date
        FROM
            dual;

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Unable to convert sysdate to GMT'
                                                   || sqlerrm);
		--halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for webservice URL is not configured in HALO_CONFIG'||sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_wallet_path
        FROM
            halo_config
        WHERE
            parameter = 'WALLET_PATH';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Parameter for api key is not configured in HALO_CONFIG'
                                                   || sqlerrm);
        --halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for api key is not configured in HALO_CONFIG'||sqlerrm);
    END;

    BEGIN
        SELECT
            value
        INTO l_sender
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_SENDER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Parameter for sender mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
        --halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for sender mail is not configured in HALO_CONFIG'||sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_receiver
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_RECEIVER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Parameter for receiver mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
        --halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for receiver mail is not configured in HALO_CONFIG'||sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            halo_char_id
        INTO l_halo_code_source
        FROM
            stg_argus_halo_idmap
        WHERE
            entity_name = 'SOURCES';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Parameter for HALO_CHAR_ID is not configured in STG_ARGUS_HALO_IDMAP'
                                                   || sqlerrm);
        --halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for HALO_CHAR_ID is not configured in STG_ARGUS_HALO_IDMAP'||sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            TO_DATE(value, 'DD-MM-YYYY HH24:MI:SS')
        INTO v_last_run
        FROM
            halo_config
        WHERE
            parameter = 'PRODUCT_LAST_RUN';

    EXCEPTION
        WHEN OTHERS THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Parameter for PRODUCT_LAST_RUN is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: VALIDATION COMPLETE');
    FOR curproduct IN (
        SELECT
            product_id
        FROM
            lm_product
        WHERE
            ( last_update_time >= v_last_run
              AND last_update_time <= v_current_date
              AND 1 != is_initial )
            OR ( deleted IS NULL
                 AND 1 = is_initial )
    ) LOOP
        SELECT
            JSON_OBJECT(
                'HALO_message' VALUE
                    JSON_OBJECT(
                        'MPD_entities' VALUE
                            JSON_OBJECT(
                                'MPS' VALUE JSON_ARRAYAGG(TREAT(get_mp_json_by_pk(curproduct.product_id) AS JSON) RETURNING CLOB)
                            RETURNING CLOB)
                    RETURNING CLOB)
            RETURNING CLOB)
        INTO l_json_request
        FROM
            dual;

        BEGIN
            IF v_halo_version < 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;
            END IF;

            IF v_halo_version >= 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;

            --  New authentication code starts here

                apex_web_service.g_request_headers(3).name := 'Tenant_ID';
                apex_web_service.g_request_headers(3).value := v_auth_tenant_id;
                apex_web_service.g_request_headers(4).name := 'Auth_Hash';
                apex_web_service.g_request_headers(4).value := v_auth_hash_key;
                apex_web_service.g_request_headers(5).name := 'Auth_Timestamp';
                apex_web_service.g_request_headers(5).value := v_auth_timestamp;

-- New authentication code ends here

            END IF;

            l_json_response := apex_web_service.make_rest_request(
                p_wallet_path => v_wallet_path,
                p_url         => webservice_url,
                p_http_method => 'POST',
                p_body        => l_json_request
            );

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: Error in loading PRODUCT.', NULL, curproduct.product_id
                ,
                               l_json_request, l_json_response);
            --halo_write_error_log ('INFO: HALO_TRANSFER_MED_PRODUCT_CONFIG: Error in loading PRODUCT: ' || curPRODUCT.PRODUCT_ID || substr(l_json_response, 1, 4000));
                RETURN;
        END;

        BEGIN
            import_halo_code_product(l_json_response, v_entity_name);
            halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: Updated to halo successfully', NULL, curproduct.product_id
            );
            halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: Response from HALO PRODUCTCONFIG endpoint', NULL
            , curproduct.product_id,
                           l_json_request, l_json_response);
            --halo_write_error_log ('INFO: HALO_TRANSFER_MED_PRODUCT_CONFIG: Response from HALO PRODUCTCONFIG endpoint: ' || substr(l_json_response, 1, 4000));
        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: Error while parsing halo response for halo and Argus ID mapping.'
                , NULL, curproduct.product_id,
                               l_json_request, l_json_response);
            --halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Error while parsing halo response for halo and Argus ID mapping.');
        END;

-- PK (05-Mar-2024) - Removed FAM_PROD_LINK call from here and added a new parameter in HALO_CONFIG table - FAM_PROD_LINK_LAST_RUN
--		BEGIN
--			HALO_TRANSFER_FAM_PROD_LINK(curPRODUCT.PRODUCT_ID);
--		EXCEPTION WHEN OTHERS THEN
--			HALO_WRITE_LOG(v_entity_name,'ERROR','HALO_TRANSFER_MED_PRODUCT_CONFIG: Error in HALO_TRANSFER_FAM_PROD_LINK procedure for linking product and Family.'|| substr(sqlerrm, 1 , 3000)||'. '|| DBMS_UTILITY.FORMAT_ERROR_BACKTRACE(),NULL,curPRODUCT.PRODUCT_ID,l_json_request, l_json_response);
--		END;

        BEGIN
            halo_transfer_prod_lic_link(curproduct.product_id);
        EXCEPTION
            WHEN OTHERS THEN
                halo_write_log(v_entity_name,
                               'ERROR',
                               'HALO_TRANSFER_MED_PRODUCT_CONFIG: Error in HALO_TRANSFER_PROD_LIC_LINK procedure for linking product and license.'
                               || substr(sqlerrm, 1, 3000)
                               || '. '
                               || dbms_utility.format_error_backtrace(),
                               NULL,
                               curproduct.product_id,
                               l_json_request,
                               l_json_response);
        END;

    END LOOP;

    halo_update_config_values('PRODUCT_LAST_RUN',
                              to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'));
    halo_write_log(v_entity_name,
                   'DEBUG',
                   'HALO_TRANSFER_MED_PRODUCT_CONFIG: COMPLETED PRODUCTS. v_current_date' || to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'
                   ));
EXCEPTION
    WHEN OTHERS THEN
        errorstring := 'HALO_TRANSFER_MED_PRODUCT_CONFIG: An unexpected error occured while transferring Product data to HALO. '
                       || substr(sqlerrm, 1, 3000)
                       || '. '
                       || dbms_utility.format_error_backtrace();

        halo_write_log(v_entity_name, 'ERROR', errorstring, NULL, NULL,
                       l_json_request, l_json_response);
        --halo_write_error_log (errorstring);

        -- Notify support mailbox of error
        halo_error_mail(
            p_from => l_sender,
            p_to   => l_receiver,
            p_sub  => 'Automatic error notification for Argus-HALO medicinal product configuration',
            p_body => 'This email is triggered due to an error in Argus-HALO integration for '
                      || webservice_url
                      || '. Please refer to the following error message: '
                      || substr(l_json_request, 1, 3000)
                      || '. '
                      || sqlerrm,
            p_port => 587
        );

END HALO_TRANSFER_MED_PRODUCT_CONFIG;
/


--------------------------------------------------------------
-- HALO_TRANSFER_FAM_PROD_LINK
--------------------------------------------------------------

CREATE OR REPLACE PROCEDURE HALO_TRANSFER_FAM_PROD_LINK (
    is_initial NUMBER DEFAULT 0
) AS

/******************************************************************************************************
--  Purpose              : LINK PRODUCT AND LICENSE
--  Input                : N/A (all products are transferred)
--  Changes:             : Created, Sudarshan Hegde, 14-Sep-2022 - HLP-2289 : HLP-3129 Sudarshan Hegde 13-Dec-2022
--  Changes:             : Updated, Added a cursor to fetch all the product IDs if a family is updated, Priyadarshan Kumar, 06-Mar-2024
******************************************************************************************************/
    l_json_request     CLOB;
    l_json_response    CLOB;
    errorstring        VARCHAR2(2000);
    webservice_url     VARCHAR2(200);
    l_sender           VARCHAR2(200);
    l_receiver         VARCHAR2(200);
    l_authorization    VARCHAR2(200);
    l_halo_code_source VARCHAR2(200);
    v_current_date     DATE := to_char(current_timestamp, 'DD-MON-YYYY HH24:MI:SS');
    v_wallet_path      VARCHAR2(200);
    v_entity_name      VARCHAR2(100) := 'PRODUCT';
    v_halo_char_id     VARCHAR2(200) := NULL;
    v_family_last_run  DATE;
    v_product_last_run DATE;


-- Added new parameters for New Authentication

    v_auth_timestamp   VARCHAR2(50 CHAR);
    v_auth_hash_key    VARCHAR2(2000);
    v_auth_tenant_id   NUMBER;
    v_auth_secret_key  NUMBER;
    v_current_utc_time VARCHAR2(100);
    v_halo_version     NUMBER;
BEGIN
    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_FAM_PROD_LINK: ENTRY');
    BEGIN
        SELECT
            value
        INTO webservice_url
        FROM
            halo_config
        WHERE
            parameter = 'HALO_PRODUCT_CONFIG_WEBSERVICE';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_FAM_PROD_LINK: '
                                                   || 'Parameter for webservice URL is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;


-- Added code to fetch HALO version

    BEGIN
        SELECT
            value
        INTO v_halo_version
        FROM
            halo_config
        WHERE
            parameter = 'HALO_VERSION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_VERSION: '
                                                   || 'Parameter for HALO_VERSION is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;




-- New authentication code starts from here


    IF v_halo_version = 5 THEN


-- Get the secret key
        BEGIN
            SELECT
                value
            INTO l_authorization
            FROM
                halo_config
            WHERE
                parameter = 'HALO_AUTHORIZATION';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'Parameter for api key is not configured in HALO_CONFIG');
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_timestamp
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TIMESTAMP';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_hash_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_HASH_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_tenant_id
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TENANT_ID';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_secret_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_SECRET_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        SELECT
            to_char(TO_TIMESTAMP_TZ(to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
                    'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS')
        INTO v_current_utc_time
        FROM
            dual;



  --  select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
   -- into v_current_utc_time
   -- from dual;

        IF (
            v_auth_hash_key IS NULL
            AND v_auth_timestamp IS NULL
        ) THEN
            UPDATE halo_config
            SET
                value = v_current_utc_time
            WHERE
                parameter = 'AUTH_TIMESTAMP';

            UPDATE halo_config
            SET
                value = (
                    SELECT
                        sys.dbms_crypto.hash(
                            utl_raw.cast_to_raw('TEN'
                                                || v_auth_tenant_id
                                                || ';'
                                                || v_current_utc_time
                                                || ';'
                                                || v_auth_secret_key),
                            4
                        )
                    FROM
                        dual
                )
            WHERE
                parameter = 'AUTH_HASH_KEY';

        ELSIF (
            v_auth_hash_key IS NOT NULL
            AND v_auth_timestamp IS NOT NULL
        ) THEN
            IF ( ( ( TO_DATE ( v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS' ) ) != TO_DATE ( v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'
            ) )
            OR ( TO_NUMBER ( to_char(TO_DATE(v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) < ( TO_NUMBER ( to_char(TO_DATE
            (v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) ) THEN
                UPDATE halo_config
                SET
                    value = v_current_utc_time
                WHERE
                    parameter = 'AUTH_TIMESTAMP';

                UPDATE halo_config
                SET
                    value = (
                        SELECT
                            sys.dbms_crypto.hash(
                                utl_raw.cast_to_raw('TEN'
                                                    || v_auth_tenant_id
                                                    || ';'
                                                    || v_current_utc_time
                                                    || ';'
                                                    || v_auth_secret_key),
                                4
                            )
                        FROM
                            dual
                    )
                WHERE
                    parameter = 'AUTH_HASH_KEY';

            END IF;
        END IF;

        SELECT
            value
        INTO v_auth_timestamp
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TIMESTAMP';

        SELECT
            value
        INTO v_auth_hash_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_HASH_KEY';

        SELECT
            value
        INTO v_auth_tenant_id
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TENANT_ID';

    END IF;

-- New authentication code ends here

    BEGIN
        SELECT
            value
        INTO v_wallet_path
        FROM
            halo_config
        WHERE
            parameter = 'WALLET_PATH';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_FAM_PROD_LINK: '
                                                   || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            CAST(from_tz(CAST(sysdate AS TIMESTAMP),(
                SELECT
                    value
                FROM
                    cmn_profile
                WHERE
                        key = 'DATABASE_TIMEZONE'
                    AND section = 'SYSTEM'
            )) AT TIME ZONE 'GMT' AS DATE)
        INTO v_current_date
        FROM
            dual;

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_FAM_PROD_LINK: '
                                                   || 'Unable to convert sysdate to GMT'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_FAM_PROD_LINK: '
                                                   || 'Parameter for api key is not configured in HALO_CONFIG'
                                                   || sqlerrm);
    END;

    BEGIN
        SELECT
            value
        INTO l_sender
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_SENDER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_FAM_PROD_LINK: '
                                                   || 'Parameter for sender mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_receiver
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_RECEIVER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_FAM_PROD_LINK: '
                                                   || 'Parameter for receiver mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            halo_char_id
        INTO l_halo_code_source
        FROM
            stg_argus_halo_idmap
        WHERE
            entity_name = 'SOURCES';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_FAM_PROD_LINK: '
                                                   || 'Parameter for HALO_CHAR_ID is not configured in STG_ARGUS_HALO_IDMAP'
                                                   || sqlerrm);
            RETURN;
    END;

    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_FAM_PROD_LINK: VALIDATION COMPLETE');


-- Added a new parameter FAM_PROD_LINK_LAST_RUN
    BEGIN
        SELECT
            TO_DATE(value, 'DD-MM-YYYY HH24:MI:SS')
        INTO v_family_last_run
        FROM
            halo_config
        WHERE
            parameter = 'FAM_PROD_LINK_LAST_RUN';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'FAM_PROD_LINK_LAST_RUN: '
                                                   || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            TO_DATE(value, 'DD-MM-YYYY HH24:MI:SS')
        INTO v_product_last_run
        FROM
            halo_config
        WHERE
            parameter = 'PRODUCT_LAST_RUN';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'FAM_PROD_LINK_LAST_RUN: '
                                                   || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;


-- Added a cursor to transfer all products linked to the family

    FOR curproduct IN (
        SELECT
            lp.product_id product_id
        FROM
            lm_product_family lpf,
            lm_product        lp
        WHERE
                lpf.family_id = lp.family_id (+)
            AND ( ( lpf.last_update_time >= v_family_last_run
                    AND lpf.last_update_time <= v_current_date )
                  OR ( lp.last_update_time >= v_product_last_run
                       AND lp.last_update_time <= v_current_date ) )
    ) LOOP
        SELECT
            JSON_OBJECT(
                'HALO_message' VALUE
                    JSON_OBJECT(
                        'MPD_entities' VALUE TREAT(get_grp_mp_json_link(curproduct.product_id) AS JSON)
                    RETURNING CLOB)
            RETURNING CLOB)
        INTO l_json_request
        FROM
            dual;

        BEGIN
            IF v_halo_version < 5 THEN
                l_json_response := empty_clob();
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;
            END IF;

            IF v_halo_version >= 5 THEN
                l_json_response := empty_clob();
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;

--  New authentication code starts here

                apex_web_service.g_request_headers(3).name := 'Tenant_ID';
                apex_web_service.g_request_headers(3).value := v_auth_tenant_id;
                apex_web_service.g_request_headers(4).name := 'Auth_Hash';
                apex_web_service.g_request_headers(4).value := v_auth_hash_key;
                apex_web_service.g_request_headers(5).name := 'Auth_Timestamp';
                apex_web_service.g_request_headers(5).value := v_auth_timestamp;

-- New authentication code ends here


            END IF;

            l_json_response := apex_web_service.make_rest_request(
                p_wallet_path => v_wallet_path,
                p_url         => webservice_url,
                p_http_method => 'POST',
                p_body        => l_json_request
            );

        EXCEPTION
            WHEN OTHERS THEN
                halo_write_log(v_entity_name,
                               'ERROR',
                               'HALO_TRANSFER_FAM_PROD_LINK: Error in loading PRODUCT.'
                               || substr(sqlerrm, 1, 1000)
                               || '. '
                               || dbms_utility.format_error_backtrace(),
                               NULL,
                               curproduct.product_id,
                               l_json_request,
                               l_json_response);
        END;

        BEGIN
            halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_FAM_PROD_LINK: Updated to halo successfully', NULL, curproduct.product_id
            );
            halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_FAM_PROD_LINK: Response from HALO PRODUCTCONFIG endpoint', NULL, curproduct.product_id
            ,
                           l_json_request, l_json_response);

        EXCEPTION
            WHEN OTHERS THEN
                halo_write_log(v_entity_name,
                               'ERROR',
                               'HALO_TRANSFER_FAM_PROD_LINK: Error while parsing halo response for halo and Argus ID mapping.'
                               || substr(sqlerrm, 1, 1000)
                               || '. '
                               || dbms_utility.format_error_backtrace(),
                               NULL,
                               curproduct.product_id,
                               l_json_request,
                               l_json_response);
        END;

        halo_write_log(v_entity_name,
                       'DEBUG',
                       'HALO_TRANSFER_FAM_PROD_LINK: COMPLETED PRODUCTS. v_current_date' || to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'
                       ));
    END LOOP;

    halo_update_config_values('FAM_PROD_LINK_LAST_RUN',
                              to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'));
EXCEPTION
    WHEN OTHERS THEN
        errorstring := 'HALO_TRANSFER_FAM_PROD_LINK: An unexpected error occured while transferring Product data to HALO. '
                       || substr(sqlerrm, 1, 3000)
                       || '. '
                       || dbms_utility.format_error_backtrace();

        halo_write_log(v_entity_name, 'ERROR', errorstring, NULL, NULL,
                       l_json_request, l_json_response);
END HALO_TRANSFER_FAM_PROD_LINK;
/

--------------------------------------------------------------
-- HALO_TRANSFER_ORGANISATION_CONFIG
--------------------------------------------------------------

create or replace PROCEDURE HALO_TRANSFER_ORGANISATION_CONFIG (IS_INITIAL NUMBER DEFAULT 0)
AS

/******************************************************************************************************
--  Purpose              : Transfer manufacturer organisations from Argus to the HALO configuration API
--  Input                : N/A (all ORGANISATION are transferred)
--  Changes:             : Created, Praveen Gupta 15-JUL-2022

******************************************************************************************************/
  l_json_request CLOB;
  l_json_response CLOB;
  errorstring VARCHAR2(2000);
  webservice_url VARCHAR2(200);
  l_sender VARCHAR2(200);
  l_receiver VARCHAR2(200);
  l_authorization VARCHAR2(200);
  l_halo_code_source VARCHAR2(200);
  v_current_date DATE := to_char(current_timestamp, 'DD-MON-YYYY HH24:MI:SS');
  v_last_run DATE;
  v_wallet_path varchar2(200);
  v_entity_name varchar2(100):='ORGANISATION';
  V_HALO_CHAR_ID varchar2(200):=NULL;
  V_OPERATION_TYPE VARCHAR(1):='1';


  -- Added new parameters for New Authentication

    v_auth_timestamp   VARCHAR2(50 CHAR);
    v_auth_hash_key    VARCHAR2(2000);
    v_auth_tenant_id   NUMBER;
    v_auth_secret_key  NUMBER;
    v_current_utc_time VARCHAR2(100);
    v_halo_version     NUMBER;

BEGIN
    HALO_WRITE_LOG(v_entity_name,'DEBUG','HALO_TRANSFER_ORGANISATION_CONFIG: ENTRY');
	BEGIN
		SELECT VALUE INTO webservice_url FROM halo_config WHERE PARAMETER = 'HALO_ORGANIZATION_CONFIG_WEBSERVICE';
	EXCEPTION WHEN NO_DATA_FOUND THEN
        HALO_WRITE_LOG(v_entity_name,'ERROR','HALO_TRANSFER_ORGANISATION_CONFIG: ' || 'Parameter for webservice URL is not configured in HALO_CONFIG'||sqlerrm);
		RETURN;
	END;


-- Added code to fetch HALO version

    BEGIN
        SELECT
            value
        INTO v_halo_version
        FROM
            halo_config
        WHERE
            parameter = 'HALO_VERSION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_VERSION: '
                                                   || 'Parameter for HALO_VERSION is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;


-- New authentication code starts from here


if v_halo_version =5 then


-- Get the secret key
    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'Parameter for api key is not configured in HALO_CONFIG');
            RETURN;
    END;


    BEGIN
        SELECT
            value
        INTO v_auth_timestamp
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TIMESTAMP';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                   || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_auth_hash_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_HASH_KEY';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                   || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_auth_tenant_id
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TENANT_ID';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                   || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_auth_secret_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_SECRET_KEY';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                   || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;

    SELECT
        to_char(TO_TIMESTAMP_TZ(to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
                'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS')
    INTO v_current_utc_time
    FROM
        dual;



  --  select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
   -- into v_current_utc_time
   -- from dual;

    IF (
        v_auth_hash_key IS NULL
        AND v_auth_timestamp IS NULL
    ) THEN


        UPDATE halo_config
        SET
            value = v_current_utc_time
        WHERE
            parameter = 'AUTH_TIMESTAMP';

        UPDATE halo_config
        SET
            value = (
                SELECT
                    sys.dbms_crypto.hash(utl_raw.cast_to_raw('TEN'
                                                             || v_auth_tenant_id
                                                             || ';'
                                                             || v_current_utc_time
                                                             || ';'
                                                             || v_auth_secret_key),
                                         4)
                FROM
                    dual
            )
        WHERE
            parameter = 'AUTH_HASH_KEY';

        elsif(v_auth_hash_key is not null and v_auth_timestamp is not null)
        then
            if(((TO_DATE(v_auth_timestamp,'YYYY-MM-DD"T"HH24:MI:SS')) != TO_DATE(v_current_utc_time,'YYYY-MM-DD"T"HH24:MI:SS')) OR
            (TO_NUMBER(TO_CHAR(TO_DATE(v_auth_timestamp,'YYYY-MM-DD"T"HH24:MI:SS'),'HH24')))< (TO_NUMBER(TO_CHAR(TO_DATE(v_current_utc_time,'YYYY-MM-DD"T"HH24:MI:SS'),'HH24')))
            )
            THEN

                    update halo_config
                    set value =v_current_utc_time
                    where PARAMETER = 'AUTH_TIMESTAMP';


                    update halo_config
                    set value =(SELECT sys.dbms_crypto.hash(utl_raw.cast_to_raw('TEN'
                                                             || v_auth_tenant_id
                                                             || ';'
                                                             || v_current_utc_time
                                                             || ';'
                                                             || v_auth_secret_key),
                                         4) FROM DUAL)
                    where parameter='AUTH_HASH_KEY';


            end if;


    END IF;

    SELECT
        value
    INTO v_auth_timestamp
    FROM
        halo_config
    WHERE
        parameter = 'AUTH_TIMESTAMP';

    SELECT
        value
    INTO v_auth_hash_key
    FROM
        halo_config
    WHERE
        parameter = 'AUTH_HASH_KEY';

    SELECT
        value
    INTO v_auth_tenant_id
    FROM
        halo_config
    WHERE
        parameter = 'AUTH_TENANT_ID';

end if;

-- New authentication code ends here



    BEGIN
		SELECT CAST (FROM_TZ (CAST (SYSDATE AS TIMESTAMP), (SELECT VALUE FROM CMN_PROFILE WHERE KEY = 'DATABASE_TIMEZONE' AND SECTION = 'SYSTEM'))
            AT TIME ZONE 'GMT' AS DATE)  INTO v_current_date FROM DUAL;
	EXCEPTION WHEN NO_DATA_FOUND THEN
        HALO_WRITE_LOG(v_entity_name,'ERROR','HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Unable to convert sysdate to GMT'||sqlerrm);
		--halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for webservice URL is not configured in HALO_CONFIG'||sqlerrm);
		RETURN;
	END;

	BEGIN
		SELECT VALUE INTO v_wallet_path FROM halo_config WHERE PARAMETER = 'WALLET_PATH';
	EXCEPTION WHEN NO_DATA_FOUND THEN
        HALO_WRITE_LOG(v_entity_name,'ERROR','HALO_TRANSFER_ORGANISATION_CONFIG: ' || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'||sqlerrm);
		RETURN;
	END;

    BEGIN
		SELECT VALUE INTO l_authorization FROM halo_config where PARAMETER = 'HALO_AUTHORIZATION';
    EXCEPTION WHEN NO_DATA_FOUND THEN
		HALO_WRITE_LOG(v_entity_name,'ERROR','HALO_TRANSFER_ORGANISATION_CONFIG: ' || 'Parameter for api key is not configured in HALO_CONFIG'||sqlerrm);
	END;

	BEGIN
		SELECT VALUE INTO l_sender FROM halo_config WHERE PARAMETER = 'HALO_ERROR_MAIL_SENDER';
    EXCEPTION WHEN NO_DATA_FOUND THEN
		HALO_WRITE_LOG(v_entity_name,'ERROR','HALO_TRANSFER_ORGANISATION_CONFIG: ' || 'Parameter for sender mail is not configured in HALO_CONFIG'||sqlerrm);
		RETURN;
	END;

	BEGIN
		SELECT VALUE INTO l_receiver FROM halo_config WHERE PARAMETER = 'HALO_ERROR_MAIL_RECEIVER';
    EXCEPTION WHEN NO_DATA_FOUND THEN
		HALO_WRITE_LOG(v_entity_name,'ERROR','HALO_TRANSFER_ORGANISATION_CONFIG: ' || 'Parameter for receiver mail is not configured in HALO_CONFIG'||sqlerrm);
		RETURN;
	END;
    BEGIN
        SELECT HALO_CHAR_ID INTO l_halo_code_source FROM STG_ARGUS_HALO_IDMAP WHERE ENTITY_NAME='SOURCES';
    EXCEPTION WHEN NO_DATA_FOUND THEN
        HALO_WRITE_LOG(v_entity_name,'ERROR','HALO_TRANSFER_ORGANISATION_CONFIG: ' || 'Parameter for HALO_CHAR_ID is not configured in STG_ARGUS_HALO_IDMAP'||sqlerrm);
		RETURN;
    END;
    BEGIN
        SELECT TO_DATE(VALUE,'DD-MM-YYYY HH24:MI:SS') INTO v_last_run FROM HALO_CONFIG WHERE parameter = 'ORGANISATION_LAST_RUN';
    EXCEPTION WHEN OTHERS THEN
        HALO_WRITE_LOG(v_entity_name,'ERROR','HALO_TRANSFER_ORGANISATION_CONFIG: ' || 'Parameter for ORGANISATION_LAST_RUN is not configured in HALO_CONFIG'||sqlerrm);
		RETURN;
    END;
    HALO_WRITE_LOG(v_entity_name,'DEBUG','HALO_TRANSFER_ORGANISATION_CONFIG: VALIDATION COMPLETE');

    FOR curMAN IN (SELECT MANUFACTURER_ID FROM LM_MANUFACTURER
                    WHERE (LAST_UPDATE_TIME >= V_LAST_RUN AND LAST_UPDATE_TIME <= V_CURRENT_DATE AND 1 != IS_INITIAL)
                            OR (DELETED IS NULL AND 1 = IS_INITIAL))
    LOOP
        HALO_WRITE_LOG(v_entity_name,'DEBUG','HALO_TRANSFER_ORGANISATION_CONFIG: PROCESSING FOR curMAN.MANUFACTURER_ID:'||curMAN.MANUFACTURER_ID);
		V_HALO_CHAR_ID := NULL;
        BEGIN
            SELECT HALO_CHAR_ID INTO V_HALO_CHAR_ID FROM STG_ARGUS_HALO_IDMAP WHERE ENTITY_NAME = v_entity_name AND ARGUS_ID = curMAN.MANUFACTURER_ID;
        EXCEPTION WHEN OTHERS THEN
            V_HALO_CHAR_ID := NULL;
            HALO_WRITE_LOG(v_entity_name,'INFO','HALO_TRANSFER_ORGANISATION_CONFIG: ' || 'IS_INITIAL: '||IS_INITIAL ||'. OPERATION_TYPE = 1 AND V_HALO_CHAR_ID IS NULL FOR ARGUS_ID:'||curMAN.MANUFACTURER_ID);
        END;
        IF(V_HALO_CHAR_ID IS NOT NULL) THEN
            V_OPERATION_TYPE := '2';
        ELSE
            V_OPERATION_TYPE := '1';
        END IF;

        SELECT
			JSON_OBJECT('HALO_message' VALUE
				JSON_OBJECT('MPD_entities' VALUE
					JSON_OBJECT('ORGANISATION' VALUE
						 JSON_ARRAYAGG (
							JSON_OBJECT (
								'HALO_CODE'             VALUE   NVL2(V_HALO_CHAR_ID,V_HALO_CHAR_ID,''),
                                'OPERATION_TYPE'    	VALUE   DECODE(NVL2(MANU.DELETED,'Y','N'),'N',V_OPERATION_TYPE,'Y','5'),
								'ORGANISATION_TYPE' 	VALUE   'In-Licensed',
								'IDENTIFIER'    		VALUE   MANU.MANUFACTURER_ID,
								'ORGANISATION'      	VALUE   MANU.MANU_NAME,
								'GIVENNAME'     		VALUE   SUBSTR(MANU.CONTACT,1,INSTR(MANU.CONTACT, ' ', 1, 1) -1),
								'MIDDLENAME'    		VALUE   CASE WHEN REGEXP_COUNT(MANU.CONTACT, ' ') > 2 THEN
                                                                    NVL(SUBSTR(MANU.CONTACT, INSTR(MANU.CONTACT, ' ', 1, 1) + 1, INSTR(MANU.CONTACT, ' ', 1, 2) - INSTR(MANU.CONTACT, ' ', 1, 1) - 1), '')
                                                                ELSE
                                                                    ''
                                                                END ,
								'FAMILYNAME'    		VALUE   CASE WHEN REGEXP_COUNT(MANU.CONTACT, ' ')>2 THEN
                                                                    NVL(SUBSTR(MANU.CONTACT, INSTR(MANU.CONTACT, ' ', 1, 2) + 1, INSTR(MANU.CONTACT, ' ', 1, 2) - 1),'')
                                                                ELSE
                                                                    NVL(SUBSTR(MANU.CONTACT, INSTR(MANU.CONTACT, ' ', 1, 1) + 1, INSTR(MANU.CONTACT, ' ', 1, 1) - 1),'')
                                                                END,
								'STREETADDRESS' 		VALUE   MANU.ADDRESS,
								'CITY'          		VALUE   MANU.CITY,
								'STATE'         		VALUE   MANU.STATE,
								'POSTCODE'      		VALUE   MANU.POSTAL_CODE,
								'COUNTRYCODE'   		VALUE   LC.A2,
								'TEL'           		VALUE   MANU.PHONE,
								'FAX'           		VALUE   MANU.FAX,
								'EMAILADDRESS'  		VALUE   MANU.EMAIL,
								'SENDER_LOCAL_CODE' 	VALUE 	MANU.MANUFACTURER_ID,
                                'HALO_CODE_SOURCE'      VALUE   l_halo_code_source
							RETURNING CLOB
						)RETURNING CLOB
					)RETURNING CLOB
				)RETURNING CLOB
			)RETURNING CLOB
		)
        INTO l_json_request
		FROM LM_MANUFACTURER MANU
           , LM_COUNTRIES LC
        WHERE MANU.MANUFACTURER_ID = curMAN.MANUFACTURER_ID
          AND MANU.COUNTRY = LC.COUNTRY(+);


        BEGIN

            if v_halo_version < 5 then

            apex_web_service.g_request_headers.DELETE;
            apex_web_service.g_request_headers(1).NAME  := 'Content-Type';
            apex_web_service.g_request_headers(1).VALUE := 'application/json';
            apex_web_service.g_request_headers(2).NAME  := 'Authorization';
            apex_web_service.g_request_headers(2).VALUE := l_authorization;

            end if;

            if v_halo_version >= 5 then

            apex_web_service.g_request_headers.DELETE;
            apex_web_service.g_request_headers(1).NAME  := 'Content-Type';
            apex_web_service.g_request_headers(1).VALUE := 'application/json';
            apex_web_service.g_request_headers(2).NAME  := 'Authorization';
            apex_web_service.g_request_headers(2).VALUE := l_authorization;


            --  New authentication code starts here

            apex_web_service.g_request_headers(3).name := 'Tenant_ID';
            apex_web_service.g_request_headers(3).value := v_auth_tenant_id;
            apex_web_service.g_request_headers(4).name := 'Auth_Hash';
            apex_web_service.g_request_headers(4).value := v_auth_hash_key;
            apex_web_service.g_request_headers(5).name := 'Auth_Timestamp';
            apex_web_service.g_request_headers(5).value := v_auth_timestamp;

-- New authentication code ends here

            end if;

            l_json_response                             := apex_web_service.make_rest_request( p_url => webservice_url, p_http_method => 'POST', p_body => l_json_request ,p_wallet_path =>v_wallet_path);
		EXCEPTION WHEN NO_DATA_FOUND THEN
            HALO_WRITE_LOG(v_entity_name,'ERROR','HALO_TRANSFER_ORGANISATION_CONFIG: Error in loading Organisation.',V_HALO_CHAR_ID,curMAN.MANUFACTURER_ID,l_json_request, l_json_response);
            RETURN;
        END;

        BEGIN
            IF(V_OPERATION_TYPE = '1') THEN
                HALO_WRITE_LOG(v_entity_name,'DEBUG','HALO_TRANSFER_ORGANISATION_CONFIG: REQUEST AND RESPONSE JSON',V_HALO_CHAR_ID,curMAN.MANUFACTURER_ID,l_json_request, l_json_response);
                IMPORT_HALO_CODE_ORGANISATION(l_json_response,v_entity_name,curMAN.MANUFACTURER_ID);
             ELSE
                HALO_WRITE_LOG(v_entity_name,'DEBUG','HALO_TRANSFER_ORGANISATION_CONFIG: NO UPDATE TO STG_ARGUS_HALO_IDMAP.',V_HALO_CHAR_ID,curMAN.MANUFACTURER_ID,l_json_request,l_json_response);
            END IF;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            HALO_WRITE_LOG(v_entity_name,'INFO','HALO_TRANSFER_ORGANISATION_CONFIG: Updated to halo successfully',V_HALO_CHAR_ID,curMAN.MANUFACTURER_ID);
            HALO_WRITE_LOG(v_entity_name,'ERROR','HALO_TRANSFER_ORGANISATION_CONFIG: Response from HALO PRODUCTCONFIG endpoint',V_HALO_CHAR_ID,curMAN.MANUFACTURER_ID,l_json_request,l_json_response);
            RETURN;
        END;
    END LOOP;
    HALO_UPDATE_CONFIG_VALUES('ORGANISATION_LAST_RUN',TO_CHAR(v_current_date,'DD-MM-YYYY HH24:MI:SS'));
    HALO_WRITE_LOG(v_entity_name,'DEBUG','HALO_TRANSFER_ORGANISATION_CONFIG: COMPLETED ORGANISATION. v_current_date'||TO_CHAR(v_current_date,'DD-MM-YYYY HH24:MI:SS'));

EXCEPTION
	WHEN OTHERS THEN
        errorstring := 'HALO_TRANSFER_ORGANISATION_CONFIG: An unexpected error occured while transferring Organisation data to HALO. '
                        || substr(sqlerrm, 1 , 3000)||'. '|| DBMS_UTILITY.FORMAT_ERROR_BACKTRACE();
        HALO_WRITE_LOG(v_entity_name,'ERROR',errorstring,NULL,NULL,l_json_request, l_json_response);
        --halo_write_error_log (errorstring);

        -- Notify support mailbox of error
          halo_error_mail
          (
            p_from => l_sender,
            p_to  => l_receiver,
            p_sub  => 'Automatic error notification for Argus-HALO organisation configuration',
            p_body => 'This email is triggered due to an error in Argus-HALO integration for ' || webservice_url ||'. Please refer to the following error message: ' || l_json_request || '. ' || sqlerrm,
            p_port => 587
          );
END HALO_TRANSFER_ORGANISATION_CONFIG;
/


--------------------------------------------------------------
-- HALO_TRANSFER_PHARM_FORM_CONFIG
--------------------------------------------------------------
CREATE OR REPLACE PROCEDURE HALO_TRANSFER_PHARM_FORM_CONFIG (
    is_initial NUMBER DEFAULT 0
) AS

/******************************************************************************************************
--  Purpose              : Transfer formulation data from Argus to the HALO configuration API
--  Input                : N/A (all pharm forms are transferred)
--  Changes:             : Created, Praveen Gupta, 08-Jul-2022
						 : Sudarshan Hegde, 23-Aug-2022 HLP-2117
******************************************************************************************************/
    l_json_request     CLOB;
    l_json_response    CLOB;
    errorstring        VARCHAR2(2000);
    webservice_url     VARCHAR2(200);
    l_sender           VARCHAR2(200);
    l_receiver         VARCHAR2(200);
    l_authorization    VARCHAR2(200);
    l_halo_code_source VARCHAR2(200);
    v_current_date     DATE := to_char(current_timestamp, 'DD-MON-YYYY HH24:MI:SS');
    v_last_run         DATE;
    v_wallet_path      VARCHAR2(200);
    v_entity_name      VARCHAR2(100) := 'PHARM_FORMS';
    v_halo_char_id     VARCHAR2(200) := NULL;
    v_operation_type   VARCHAR(1) := '1';


-- Added new parameters for New Authentication

    v_auth_timestamp   VARCHAR2(50 CHAR);
    v_auth_hash_key    VARCHAR2(2000);
    v_auth_tenant_id   NUMBER;
    v_auth_secret_key  NUMBER;
    v_current_utc_time VARCHAR2(100);
    v_halo_version     NUMBER;
BEGIN
    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PHARM_FORM_CONFIG: ENTRY');
    BEGIN
        SELECT
            value
        INTO webservice_url
        FROM
            halo_config
        WHERE
            parameter = 'HALO_PRODUCT_CONFIG_WEBSERVICE';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PHARM_FORM_CONFIG: '
                                                   || 'Parameter for webservice URL is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;


-- Added code to fetch HALO version

    BEGIN
        SELECT
            value
        INTO v_halo_version
        FROM
            halo_config
        WHERE
            parameter = 'HALO_VERSION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_VERSION: '
                                                   || 'Parameter for HALO_VERSION is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;


-- New authentication code starts from here


    IF v_halo_version = 5 THEN


-- Get the secret key
        BEGIN
            SELECT
                value
            INTO l_authorization
            FROM
                halo_config
            WHERE
                parameter = 'HALO_AUTHORIZATION';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'Parameter for api key is not configured in HALO_CONFIG');
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_timestamp
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TIMESTAMP';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_hash_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_HASH_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_tenant_id
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TENANT_ID';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_secret_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_SECRET_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        SELECT
            to_char(TO_TIMESTAMP_TZ(to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
                    'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS')
        INTO v_current_utc_time
        FROM
            dual;



  --  select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
   -- into v_current_utc_time
   -- from dual;

        IF (
            v_auth_hash_key IS NULL
            AND v_auth_timestamp IS NULL
        ) THEN
            UPDATE halo_config
            SET
                value = v_current_utc_time
            WHERE
                parameter = 'AUTH_TIMESTAMP';

            UPDATE halo_config
            SET
                value = (
                    SELECT
                        sys.dbms_crypto.hash(
                            utl_raw.cast_to_raw('TEN'
                                                || v_auth_tenant_id
                                                || ';'
                                                || v_current_utc_time
                                                || ';'
                                                || v_auth_secret_key),
                            4
                        )
                    FROM
                        dual
                )
            WHERE
                parameter = 'AUTH_HASH_KEY';

        ELSIF (
            v_auth_hash_key IS NOT NULL
            AND v_auth_timestamp IS NOT NULL
        ) THEN
            IF ( ( ( TO_DATE ( v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS' ) ) != TO_DATE ( v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'
            ) )
            OR ( TO_NUMBER ( to_char(TO_DATE(v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) < ( TO_NUMBER ( to_char(TO_DATE
            (v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) ) THEN
                UPDATE halo_config
                SET
                    value = v_current_utc_time
                WHERE
                    parameter = 'AUTH_TIMESTAMP';

                UPDATE halo_config
                SET
                    value = (
                        SELECT
                            sys.dbms_crypto.hash(
                                utl_raw.cast_to_raw('TEN'
                                                    || v_auth_tenant_id
                                                    || ';'
                                                    || v_current_utc_time
                                                    || ';'
                                                    || v_auth_secret_key),
                                4
                            )
                        FROM
                            dual
                    )
                WHERE
                    parameter = 'AUTH_HASH_KEY';

            END IF;
        END IF;

        SELECT
            value
        INTO v_auth_timestamp
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TIMESTAMP';

        SELECT
            value
        INTO v_auth_hash_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_HASH_KEY';

        SELECT
            value
        INTO v_auth_tenant_id
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TENANT_ID';

    END IF;

-- New authentication code ends here



    BEGIN
        SELECT
            value
        INTO v_wallet_path
        FROM
            halo_config
        WHERE
            parameter = 'WALLET_PATH';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PHARM_FORM_CONFIG: '
                                                   || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            CAST(from_tz(CAST(sysdate AS TIMESTAMP),(
                SELECT
                    value
                FROM
                    cmn_profile
                WHERE
                        key = 'DATABASE_TIMEZONE'
                    AND section = 'SYSTEM'
            )) AT TIME ZONE 'GMT' AS DATE)
        INTO v_current_date
        FROM
            dual;

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Unable to convert sysdate to GMT'
                                                   || sqlerrm);
		--halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for webservice URL is not configured in HALO_CONFIG'||sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PHARM_FORM_CONFIG: '
                                                   || 'Parameter for api key is not configured in HALO_CONFIG'
                                                   || sqlerrm);
    END;

    BEGIN
        SELECT
            value
        INTO l_sender
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_SENDER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PHARM_FORM_CONFIG: '
                                                   || 'Parameter for sender mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_receiver
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_RECEIVER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PHARM_FORM_CONFIG: '
                                                   || 'Parameter for receiver mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            halo_char_id
        INTO l_halo_code_source
        FROM
            stg_argus_halo_idmap
        WHERE
            entity_name = 'SOURCES';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PHARM_FORM_CONFIG: '
                                                   || 'Parameter for HALO_CHAR_ID is not configured in STG_ARGUS_HALO_IDMAP'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            TO_DATE(value, 'DD-MM-YYYY HH24:MI:SS')
        INTO v_last_run
        FROM
            halo_config
        WHERE
            parameter = 'PHARM_FORM_LAST_RUN';

    EXCEPTION
        WHEN OTHERS THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PHARM_FORM_CONFIG: '
                                                   || 'Parameter for PHARM_FORM_LAST_RUN is not configured OR Incorrect, should in DD-MM-YYYY HH24:MI:SS format in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;


    --Generate JOSN for all pharm forms in Argus DB.
    FOR curphrfom IN (
        SELECT
            formulation_id
        FROM
            lm_formulation
        WHERE
            ( last_update_time >= v_last_run
              AND last_update_time <= v_current_date
              AND 1 != is_initial )
            OR ( deleted IS NULL
                 AND 1 = is_initial )
        ORDER BY
            formulation_id
    ) LOOP
        halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PHARM_FORM_CONFIG: PROCESSING FOR curPHRFOM.FORMULATION_ID:' || curphrfom.formulation_id
        );
        v_halo_char_id := NULL;
        BEGIN
            SELECT
                halo_char_id
            INTO v_halo_char_id
            FROM
                stg_argus_halo_idmap
            WHERE
                    entity_name = v_entity_name
                AND argus_id = curphrfom.formulation_id;

        EXCEPTION
            WHEN OTHERS THEN
                v_halo_char_id := NULL;
                halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_PHARM_FORM_CONFIG: '
                                                      || 'IS_INITIAL: '
                                                      || is_initial
                                                      || '. OPERATION_TYPE = 1 AND V_HALO_CHAR_ID IS NULL FOR ARGUS_ID:'
                                                      || curphrfom.formulation_id);

        END;

        IF ( v_halo_char_id IS NOT NULL ) THEN
            v_operation_type := '2';
        ELSE
            v_operation_type := '1';
        END IF;

        SELECT
            JSON_OBJECT(
                'HALO_message' VALUE
                    JSON_OBJECT(
                        'MPD_entities' VALUE
                            JSON_OBJECT(
                                'PHARM_FORM' VALUE JSON_ARRAYAGG(
                                    JSON_OBJECT(
                                        'HALO_CODE' VALUE nvl2(v_halo_char_id, v_halo_char_id, ''),
                                                'OPERATION_TYPE' VALUE decode(
                                            nvl2(lf.deleted, 'Y', 'N'),
                                            'N',
                                            v_operation_type,
                                            'Y',
                                            '5'
                                        ),
                                                'TERM_TYPE_CODE' VALUE 'STD',
                                                'PHARM_FORM_NAME' VALUE lf.formulation,
                                                'COMMENT_PHARM_FORM' VALUE lf.formulation_j,
                                                'DEPRECATED_FLAG' VALUE decode(
                                            nvl2(lf.deleted,
                                                 1,
                                                 nvl(lf.display, 0)),
                                            0,
                                            1,
                                            1,
                                            0
                                        ),
                                                'SENDER_LOCAL_CODE' VALUE lf.formulation_id,
                                                'NULLIFIED_DATE' VALUE lf.deleted,
                                                'HALO_CODE_SOURCE' VALUE l_halo_code_source
                                    RETURNING CLOB)
                                RETURNING CLOB)
                            RETURNING CLOB)
                    RETURNING CLOB)
            RETURNING CLOB)
        INTO l_json_request
        FROM
            lm_formulation lf
        WHERE
            lf.formulation_id = curphrfom.formulation_id;

		--Call HALO API to push pharm forms
        BEGIN
            IF v_halo_version < 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;
            END IF;

            IF v_halo_version >= 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;

            --  New authentication code starts here

                apex_web_service.g_request_headers(3).name := 'Tenant_ID';
                apex_web_service.g_request_headers(3).value := v_auth_tenant_id;
                apex_web_service.g_request_headers(4).name := 'Auth_Hash';
                apex_web_service.g_request_headers(4).value := v_auth_hash_key;
                apex_web_service.g_request_headers(5).name := 'Auth_Timestamp';
                apex_web_service.g_request_headers(5).value := v_auth_timestamp;

-- New authentication code ends here

            END IF;

            l_json_response := apex_web_service.make_rest_request(
                p_wallet_path => v_wallet_path,
                p_url         => webservice_url,
                p_http_method => 'POST',
                p_body        => l_json_request
            );

            halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PHARM_FORM_CONFIG: Error in loading PHARM_FORM.', v_halo_char_id, curphrfom.formulation_id
            ,
                           l_json_request, l_json_response);

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PHARM_FORM_CONFIG: Error in loading PHARM_FORM.', v_halo_char_id
                , curphrfom.formulation_id,
                               l_json_request, l_json_response);

                RETURN;
        END;

		--Parse API response json and insert in mapping table for argus and halo IDs
        BEGIN
            IF ( v_operation_type = '1' ) THEN
                import_halo_code_pharm_forms(l_json_response, v_entity_name);
                halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_PHARM_FORM_CONFIG: Updated to halo successfully', v_halo_char_id
                , curphrfom.formulation_id);
                halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PHARM_FORM_CONFIG: Response from HALO PRODUCT CONFIG endpoint',
                v_halo_char_id, curphrfom.formulation_id,
                               l_json_request, l_json_response);

            ELSE
                halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PHARM_FORM_CONFIG: NO UPDATE TO STG_ARGUS_HALO_IDMAP.', v_halo_char_id
                , curphrfom.formulation_id,
                               l_json_request, l_json_response);
            END IF;
        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PHARM_FORM_CONFIG: Error while parsing halo response for halo and Argus ID mapping.'
                , v_halo_char_id, curphrfom.formulation_id,
                               l_json_request, l_json_response);
        END;

    END LOOP;

    halo_update_config_values('PHARM_FORM_LAST_RUN',
                              to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'));
    halo_write_log(v_entity_name,
                   'DEBUG',
                   'HALO_TRANSFER_PHARM_FORM_CONFIG: COMPLETED PHARM_FORMS. v_current_date' || to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'
                   ));
EXCEPTION
    WHEN OTHERS THEN
        errorstring := 'HALO_TRANSFER_PHARM_FORM_CONFIG: An unexpected error occured while transferring PHARM FORM data to HALO. '
                       || substr(sqlerrm, 1, 3000)
                       || '. '
                       || dbms_utility.format_error_backtrace();

        halo_write_log(v_entity_name, 'ERROR', errorstring, NULL, NULL,
                       l_json_request, l_json_response);

        -- Notify support mailbox of error
        halo_error_mail(
            p_from => l_sender,
            p_to   => l_receiver,
            p_sub  => 'Automatic error notification for Argus-HALO medicinal PHARM FORM configuration',
            p_body => 'This email is triggered due to an error in Argus-HALO integration for '
                      || webservice_url
                      || '. Please refer to the following error message: '
                      || l_json_request
                      || '. '
                      || sqlerrm,
            p_port => 587
        );

END HALO_TRANSFER_PHARM_FORM_CONFIG;
/


--------------------------------------------------------------
-- HALO_TRANSFER_PROD_LIC_LINK
--------------------------------------------------------------
CREATE OR REPLACE PROCEDURE HALO_TRANSFER_PROD_LIC_LINK (
    is_initial NUMBER DEFAULT 0,
    argus_id   NUMBER DEFAULT 0,
    is_error   NUMBER DEFAULT 0
) AS

/******************************************************************************************************
--  Purpose              : LINK PRODUCT AND LICENSE
--  Input                : N/A (all products are transferred)
--  Changes:             : Created, Sudarshan Hegde, 14-Sep-2022 - HLP-2289
                                                                                          : HLP-3129 Sudarshan Hegde 13-Dec-2022
                                                                                          : HLP-3083 Sudarshan Hegde Changes to handle linking seprately
                                                                                          : HLP-4640 Sudarshan Hegde 17-APR-2022
                                                                                          : HLP-4677         Sudarshan Hegde 18-APR-2022 Removed Return in the loop and made response was made as empty clob
                                                                                          : HLP-4677 Sudarshan Hegde 19-APR-2022
                                                                                          : HLP-4677 Sudarshan Hegde 19-APR-2022               - Added distinct
--  Changes:            : Updated to bring all PROD-LIC linking, Priyadarshan Kumar, 06-Mar-2024
******************************************************************************************************/
    l_json_request     CLOB;
    l_json_response    CLOB;
    errorstring        VARCHAR2(2000);
    webservice_url     VARCHAR2(200);
    l_sender           VARCHAR2(200);
    l_receiver         VARCHAR2(200);
    l_authorization    VARCHAR2(200);
    l_halo_code_source VARCHAR2(200);
    v_current_date     DATE := sysdate;
    v_last_run         DATE;
    v_wallet_path      VARCHAR2(200);
    v_entity_name      VARCHAR2(100) := 'PRODUCT_LIC_LINK';
    v_halo_char_id     VARCHAR2(200) := NULL;

    -- Added new parameters for New Authentication

    v_auth_timestamp   VARCHAR2(50 CHAR);
    v_auth_hash_key    VARCHAR2(2000);
    v_auth_tenant_id   NUMBER;
    v_auth_secret_key  NUMBER;
    v_current_utc_time VARCHAR2(100);
    v_halo_version     NUMBER;
BEGIN
    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PROD_LIC_LINK: ENTRY');



    -- Added code to fetch HALO version

    BEGIN
        SELECT
            value
        INTO v_halo_version
        FROM
            halo_config
        WHERE
            parameter = 'HALO_VERSION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_VERSION: '
                                                   || 'Parameter for HALO_VERSION is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;



-- New authentication code starts from here


    IF v_halo_version = 5 THEN


-- Get the secret key
        BEGIN
            SELECT
                value
            INTO l_authorization
            FROM
                halo_config
            WHERE
                parameter = 'HALO_AUTHORIZATION';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'Parameter for api key is not configured in HALO_CONFIG');
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_timestamp
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TIMESTAMP';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_hash_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_HASH_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_tenant_id
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TENANT_ID';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_secret_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_SECRET_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        SELECT
            to_char(TO_TIMESTAMP_TZ(to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
                    'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS')
        INTO v_current_utc_time
        FROM
            dual;



  --  select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
   -- into v_current_utc_time
   -- from dual;

        IF (
            v_auth_hash_key IS NULL
            AND v_auth_timestamp IS NULL
        ) THEN
            UPDATE halo_config
            SET
                value = v_current_utc_time
            WHERE
                parameter = 'AUTH_TIMESTAMP';

            UPDATE halo_config
            SET
                value = (
                    SELECT
                        sys.dbms_crypto.hash(
                            utl_raw.cast_to_raw('TEN'
                                                || v_auth_tenant_id
                                                || ';'
                                                || v_current_utc_time
                                                || ';'
                                                || v_auth_secret_key),
                            4
                        )
                    FROM
                        dual
                )
            WHERE
                parameter = 'AUTH_HASH_KEY';

        ELSIF (
            v_auth_hash_key IS NOT NULL
            AND v_auth_timestamp IS NOT NULL
        ) THEN
            IF ( ( ( TO_DATE ( v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS' ) ) != TO_DATE ( v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'
            ) )
            OR ( TO_NUMBER ( to_char(TO_DATE(v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) < ( TO_NUMBER ( to_char(TO_DATE
            (v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) ) THEN
                UPDATE halo_config
                SET
                    value = v_current_utc_time
                WHERE
                    parameter = 'AUTH_TIMESTAMP';

                UPDATE halo_config
                SET
                    value = (
                        SELECT
                            sys.dbms_crypto.hash(
                                utl_raw.cast_to_raw('TEN'
                                                    || v_auth_tenant_id
                                                    || ';'
                                                    || v_current_utc_time
                                                    || ';'
                                                    || v_auth_secret_key),
                                4
                            )
                        FROM
                            dual
                    )
                WHERE
                    parameter = 'AUTH_HASH_KEY';

            END IF;
        END IF;

        SELECT
            value
        INTO v_auth_timestamp
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TIMESTAMP';

        SELECT
            value
        INTO v_auth_hash_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_HASH_KEY';

        SELECT
            value
        INTO v_auth_tenant_id
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TENANT_ID';

    END IF;

-- New authentication code ends here


    BEGIN
        SELECT
            value
        INTO webservice_url
        FROM
            halo_config
        WHERE
            parameter = 'HALO_PRODUCT_CONFIG_WEBSERVICE';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PROD_LIC_LINK: '
                                                   || 'Parameter for webservice URL is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_wallet_path
        FROM
            halo_config
        WHERE
            parameter = 'WALLET_PATH';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PROD_LIC_LINK: '
                                                   || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            CAST(from_tz(CAST(sysdate AS TIMESTAMP),(
                SELECT
                    value
                FROM
                    cmn_profile
                WHERE
                        key = 'DATABASE_TIMEZONE'
                    AND section = 'SYSTEM'
            )) AT TIME ZONE 'GMT' AS DATE)
        INTO v_current_date
        FROM
            dual;

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PROD_LIC_LINK: '
                                                   || 'Unable to convert sysdate to GMT'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PROD_LIC_LINK: '
                                                   || 'Parameter for api key is not configured in HALO_CONFIG'
                                                   || sqlerrm);
    END;

    BEGIN
        SELECT
            value
        INTO l_sender
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_SENDER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PROD_LIC_LINK: '
                                                   || 'Parameter for sender mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_receiver
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_RECEIVER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PROD_LIC_LINK: '
                                                   || 'Parameter for receiver mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            halo_char_id
        INTO l_halo_code_source
        FROM
            stg_argus_halo_idmap
        WHERE
            entity_name = 'SOURCES';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PROD_LIC_LINK: '
                                                   || 'Parameter for HALO_CHAR_ID is not configured in STG_ARGUS_HALO_IDMAP'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            TO_DATE(value, 'DD-MM-YYYY HH24:MI:SS')
        INTO v_last_run
        FROM
            halo_config
        WHERE
            parameter = 'LINKING_PROD_LIC_LAST_RUN';

    EXCEPTION
        WHEN OTHERS THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Parameter for LINKING_PROD_LIC_LAST_RUN is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PROD_LIC_LINK: VALIDATION COMPLETE');
    FOR curproduct IN (
        (
            SELECT DISTINCT
                product_id
            FROM
                lm_lic_products
            WHERE
                ( last_update_time >= v_last_run
                  AND last_update_time <= v_current_date
                  AND 1 != is_initial
                  AND is_error = 0 )
                OR ( deleted IS NULL
                     AND 1 = is_initial
                     AND is_error = 0 )
                OR ( is_error = 1
                     AND product_id = argus_id )
        )
        UNION
        (
            SELECT DISTINCT
                product_id
            FROM
                lm_product
            WHERE
                ( last_update_time >= v_last_run
                  AND last_update_time <= v_current_date
                  AND 1 != is_initial
                  AND is_error = 0 )
                OR ( deleted IS NULL
                     AND 1 = is_initial
                     AND is_error = 0 )
                OR ( is_error = 1
                     AND product_id = argus_id )
        )
    ) LOOP
        SELECT
            JSON_OBJECT(
                'HALO_message' VALUE
                    JSON_OBJECT(
                        'MPD_entities' VALUE TREAT(get_mp_lic_json_link(curproduct.product_id) AS JSON)
                    RETURNING CLOB)
            RETURNING CLOB)
        INTO l_json_request
        FROM
            dual;

        BEGIN
            IF v_halo_version < 5 THEN
                l_json_response := empty_clob();
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;
            END IF;

            IF v_halo_version >= 5 THEN
                l_json_response := empty_clob();
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;

            --  New authentication code starts here

                apex_web_service.g_request_headers(3).name := 'Tenant_ID';
                apex_web_service.g_request_headers(3).value := v_auth_tenant_id;
                apex_web_service.g_request_headers(4).name := 'Auth_Hash';
                apex_web_service.g_request_headers(4).value := v_auth_hash_key;
                apex_web_service.g_request_headers(5).name := 'Auth_Timestamp';
                apex_web_service.g_request_headers(5).value := v_auth_timestamp;

-- New authentication code ends here

            END IF;

            l_json_response := apex_web_service.make_rest_request(
                p_wallet_path => v_wallet_path,
                p_url         => webservice_url,
                p_http_method => 'POST',
                p_body        => l_json_request
            );

        EXCEPTION
            WHEN OTHERS THEN
                halo_write_log(v_entity_name,
                               'ERROR',
                               'HALO_TRANSFER_PROD_LIC_LINK: Error in loading PRODUCT.'
                               || substr(sqlerrm, 1, 1000)
                               || '. '
                               || dbms_utility.format_error_backtrace(),
                               NULL,
                               curproduct.product_id,
                               l_json_request,
                               l_json_response);
        END;

        BEGIN
            halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_PROD_LIC_LINK: Updated to halo successfully', NULL, curproduct.product_id
            );
            halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PROD_LIC_LINK: Response from HALO PRODUCTCONFIG endpoint', NULL, curproduct.product_id
            ,
                           l_json_request, l_json_response);

        EXCEPTION
            WHEN OTHERS THEN
                halo_write_log(v_entity_name,
                               'ERROR',
                               'HALO_TRANSFER_PROD_LIC_LINK: Error while parsing halo response for halo and Argus ID mapping.'
                               || substr(sqlerrm, 1, 1000)
                               || '. '
                               || dbms_utility.format_error_backtrace(),
                               NULL,
                               curproduct.product_id,
                               l_json_request,
                               l_json_response);
        END;

    END LOOP;

    halo_update_config_values('LINKING_PROD_LIC_LAST_RUN',
                              to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'));
    halo_write_log(v_entity_name,
                   'DEBUG',
                   'HALO_TRANSFER_PROD_LIC_LINK: COMPLETED PRODUCTS. v_current_date' || to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'
                   ));
EXCEPTION
    WHEN OTHERS THEN
        errorstring := 'HALO_TRANSFER_PROD_LIC_LINK: An unexpected error occured while transferring Product data to HALO. '
                       || substr(sqlerrm, 1, 3000)
                       || '. '
                       || dbms_utility.format_error_backtrace();

        halo_write_log(v_entity_name, 'ERROR', errorstring, NULL, NULL,
                       l_json_request, l_json_response);


        -- Notify support mailbox of error
        halo_error_mail(
            p_from => l_sender,
            p_to   => l_receiver,
            p_sub  => 'Automatic error notification for Argus-HALO medicinal product configuration',
            p_body => 'This email is triggered due to an error in Argus-HALO integration for '
                      || webservice_url
                      || '. Please refer to the following error message: '
                      || substr(l_json_request, 1, 3000)
                      || '. '
                      || sqlerrm,
            p_port => 587
        );

END HALO_TRANSFER_PROD_LIC_LINK;
/

--------------------------------------------------------------
-- HALO_TRANSFER_PRODUCT_FAMILY_CONFIG
--------------------------------------------------------------
CREATE OR REPLACE PROCEDURE HALO_TRANSFER_PRODUCT_FAMILY_CONFIG (
    is_initial NUMBER DEFAULT 0
) AS

/******************************************************************************************************
--  Purpose              : Transfer product family data from Argus to the HALO configuration API
--  Input                : N/A (all PRODUCT_FAMILY family are transferred)
--  Changes:             : Created, Praveen Gupta 14-JUL-2022
--                       : CSL custom deployment. Updated owner_org_code, PSP, 2026-Jun-25 

******************************************************************************************************/
    l_json_request     CLOB;
    l_json_response    CLOB;
    errorstring        VARCHAR2(2000);
    webservice_url     VARCHAR2(200);
    l_sender           VARCHAR2(200);
    l_receiver         VARCHAR2(200);
    l_authorization    VARCHAR2(200);
    l_halo_code_source VARCHAR2(200);
    v_current_date     DATE := to_char(current_timestamp, 'DD-MON-YYYY HH24:MI:SS');
    v_last_run         DATE;
    v_wallet_path      VARCHAR2(200);
    v_entity_name      VARCHAR2(100) := 'PRODUCT_FAMILY';
    v_halo_char_id     VARCHAR2(200) := NULL;
    v_operation_type   VARCHAR(1) := '1';


    -- Added new parameters for New Authentication

    v_auth_timestamp   VARCHAR2(50 CHAR);
    v_auth_hash_key    VARCHAR2(2000);
    v_auth_tenant_id   NUMBER;
    v_auth_secret_key  NUMBER;
    v_current_utc_time VARCHAR2(100);
    v_halo_version     NUMBER;
BEGIN
    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: ENTRY');
    BEGIN
        SELECT
            value
        INTO webservice_url
        FROM
            halo_config
        WHERE
            parameter = 'HALO_PRODUCT_CONFIG_WEBSERVICE';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: '
                                                   || 'Parameter for webservice URL is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;



-- Added code to fetch HALO version

    BEGIN
        SELECT
            value
        INTO v_halo_version
        FROM
            halo_config
        WHERE
            parameter = 'HALO_VERSION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_VERSION: '
                                                   || 'Parameter for HALO_VERSION is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;




-- New authentication code starts from here


    IF v_halo_version = 5 THEN


-- Get the secret key
        BEGIN
            SELECT
                value
            INTO l_authorization
            FROM
                halo_config
            WHERE
                parameter = 'HALO_AUTHORIZATION';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'Parameter for api key is not configured in HALO_CONFIG');
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_timestamp
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TIMESTAMP';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_hash_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_HASH_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_tenant_id
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TENANT_ID';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_secret_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_SECRET_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        SELECT
            to_char(TO_TIMESTAMP_TZ(to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
                    'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS')
        INTO v_current_utc_time
        FROM
            dual;



  --  select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
   -- into v_current_utc_time
   -- from dual;

        IF (
            v_auth_hash_key IS NULL
            AND v_auth_timestamp IS NULL
        ) THEN
            UPDATE halo_config
            SET
                value = v_current_utc_time
            WHERE
                parameter = 'AUTH_TIMESTAMP';

            UPDATE halo_config
            SET
                value = (
                    SELECT
                        sys.dbms_crypto.hash(
                            utl_raw.cast_to_raw('TEN'
                                                || v_auth_tenant_id
                                                || ';'
                                                || v_current_utc_time
                                                || ';'
                                                || v_auth_secret_key),
                            4
                        )
                    FROM
                        dual
                )
            WHERE
                parameter = 'AUTH_HASH_KEY';

        ELSIF (
            v_auth_hash_key IS NOT NULL
            AND v_auth_timestamp IS NOT NULL
        ) THEN
            IF ( ( ( TO_DATE ( v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS' ) ) != TO_DATE ( v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'
            ) )
            OR ( TO_NUMBER ( to_char(TO_DATE(v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) < ( TO_NUMBER ( to_char(TO_DATE
            (v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) ) THEN
                UPDATE halo_config
                SET
                    value = v_current_utc_time
                WHERE
                    parameter = 'AUTH_TIMESTAMP';

                UPDATE halo_config
                SET
                    value = (
                        SELECT
                            sys.dbms_crypto.hash(
                                utl_raw.cast_to_raw('TEN'
                                                    || v_auth_tenant_id
                                                    || ';'
                                                    || v_current_utc_time
                                                    || ';'
                                                    || v_auth_secret_key),
                                4
                            )
                        FROM
                            dual
                    )
                WHERE
                    parameter = 'AUTH_HASH_KEY';

            END IF;
        END IF;

        SELECT
            value
        INTO v_auth_timestamp
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TIMESTAMP';

        SELECT
            value
        INTO v_auth_hash_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_HASH_KEY';

        SELECT
            value
        INTO v_auth_tenant_id
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TENANT_ID';

    END IF;

-- New authentication code ends here



    BEGIN
        SELECT
            CAST(from_tz(CAST(sysdate AS TIMESTAMP),(
                SELECT
                    value
                FROM
                    cmn_profile
                WHERE
                        key = 'DATABASE_TIMEZONE'
                    AND section = 'SYSTEM'
            )) AT TIME ZONE 'GMT' AS DATE)
        INTO v_current_date
        FROM
            dual;

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Unable to convert sysdate to GMT'
                                                   || sqlerrm);
		--halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for webservice URL is not configured in HALO_CONFIG'||sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_wallet_path
        FROM
            halo_config
        WHERE
            parameter = 'WALLET_PATH';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: '
                                                   || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: '
                                                   || 'Parameter for api key is not configured in HALO_CONFIG'
                                                   || sqlerrm);
    END;

    BEGIN
        SELECT
            value
        INTO l_sender
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_SENDER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: '
                                                   || 'Parameter for sender mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_receiver
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_RECEIVER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: '
                                                   || 'Parameter for receiver mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            halo_char_id
        INTO l_halo_code_source
        FROM
            stg_argus_halo_idmap
        WHERE
            entity_name = 'SOURCES';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: '
                                                   || 'Parameter for HALO_CHAR_ID is not configured in STG_ARGUS_HALO_IDMAP'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            TO_DATE(value, 'DD-MM-YYYY HH24:MI:SS')
        INTO v_last_run
        FROM
            halo_config
        WHERE
            parameter = 'PRODUCT_FAMILY_LAST_RUN';

    EXCEPTION
        WHEN OTHERS THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: '
                                                   || 'Parameter for PRODUCT_FAMILY_LAST_RUN is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: VALIDATION COMPLETED');
    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: V_CURRENT_DATE'
                                           || v_current_date
                                           || '. V_LAST_RUN'
                                           || v_last_run
                                           || '. IS_INITIAL'
                                           || is_initial);

    FOR curfamily IN (
        SELECT
            family_id
        FROM
            lm_product_family
        WHERE
            ( last_update_time >= v_last_run
              AND last_update_time <= v_current_date
              AND 1 != is_initial )
            OR ( deleted IS NULL
                 AND 1 = is_initial )
    ) LOOP
        halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: PROCESS STARTED FOR FAMILY_ID:' || curfamily.family_id
        );
        v_halo_char_id := NULL;
        BEGIN
            SELECT
                halo_char_id
            INTO v_halo_char_id
            FROM
                stg_argus_halo_idmap
            WHERE
                    entity_name = v_entity_name
                AND argus_id = curfamily.family_id;

        EXCEPTION
            WHEN OTHERS THEN
                v_halo_char_id := NULL;
                halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: '
                                                      || 'IS_INITIAL: '
                                                      || is_initial
                                                      || '. OPERATION_TYPE = 1 AND V_HALO_CHAR_ID IS NULL FOR ARGUS_ID:'
                                                      || curfamily.family_id);

        END;

        IF ( v_halo_char_id IS NOT NULL ) THEN
            v_operation_type := '2';
        ELSE
            v_operation_type := '1';
        END IF;
        --Generate JSON for all product families in Argus DB
        SELECT
            JSON_OBJECT(
                'HALO_message' VALUE
                    JSON_OBJECT(
                        'MPD_entities' VALUE
                            JSON_OBJECT(
                                'MP_GROUPS' VALUE JSON_ARRAYAGG(
                                    JSON_OBJECT(
                                        'HALO_CODE' VALUE nvl2(v_halo_char_id, v_halo_char_id, ''),
                                                'OPERATION_TYPE' VALUE decode(
                                            nvl2(lpf.deleted, 'Y', 'N'),
                                            'N',
                                            v_operation_type,
                                            'Y',
                                            '5'
                                        ),
                                                'PRODUCT_TYPE_CODE' VALUE 'MEDICINE',
                                                'NAME_VARIATION_TYPE_CODE' VALUE 'GRP_PGR',
                                                'GROUP_NAME' VALUE lpf.name,
                                                'SENDER_LOCAL_CODE' VALUE lpf.family_id,
                                                'HALO_CODE_SOURCE' VALUE l_halo_code_source,
                                                'OWNER_ORG_CODE' VALUE 'ORG35187'
                                    RETURNING CLOB)
                                RETURNING CLOB)
                            RETURNING CLOB)
                    RETURNING CLOB)
            RETURNING CLOB)
        INTO l_json_request
        FROM
            lm_product_family lpf
        WHERE
            lpf.family_id = curfamily.family_id;

		--Push generated JSON to halo API for import
        BEGIN
            IF v_halo_version < 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;
            END IF;

            IF v_halo_version >= 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;

--  New authentication code starts here

                apex_web_service.g_request_headers(3).name := 'Tenant_ID';
                apex_web_service.g_request_headers(3).value := v_auth_tenant_id;
                apex_web_service.g_request_headers(4).name := 'Auth_Hash';
                apex_web_service.g_request_headers(4).value := v_auth_hash_key;
                apex_web_service.g_request_headers(5).name := 'Auth_Timestamp';
                apex_web_service.g_request_headers(5).value := v_auth_timestamp;

-- New authentication code ends here

            END IF;

            l_json_response := apex_web_service.make_rest_request(
                p_body        => l_json_request,
                p_wallet_path => v_wallet_path,
                p_url         => webservice_url,
                p_http_method => 'POST'
            );

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: Error in loading PRODUCT.', v_halo_char_id
                , curfamily.family_id,
                               l_json_request, l_json_response);

                RETURN;
        END;

        BEGIN
            IF ( v_operation_type = '1' ) THEN
                import_halo_code_product_family(l_json_response, v_entity_name);
                halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: Updated to halo successfully', v_halo_char_id
                , curfamily.family_id);
                halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: Response from HALO PRODUCTCONFIG endpoint'
                , v_halo_char_id, curfamily.family_id,
                               l_json_request, l_json_response);

            ELSE
                halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: NO UPDATE TO STG_ARGUS_HALO_IDMAP.', v_halo_char_id
                , curfamily.family_id,
                               l_json_request, l_json_response);
            END IF;
        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: Error while parsing halo response for halo and Argus ID mapping.'
                , v_halo_char_id, curfamily.family_id,
                               l_json_request, l_json_response);
        END;

    END LOOP;

    halo_update_config_values('PRODUCT_FAMILY_LAST_RUN',
                              to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'));
    halo_write_log(v_entity_name,
                   'DEBUG',
                   'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: COMPLETED PRODUCT_FAMILY. v_current_date' || to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'
                   ));
EXCEPTION
    WHEN OTHERS THEN
        errorstring := 'HALO_TRANSFER_PRODUCT_FAMILY_CONFIG: An unexpected error occured while transferring Product data to HALO. '
                       || substr(sqlerrm, 1, 3000)
                       || '. '
                       || dbms_utility.format_error_backtrace();

        halo_write_log(v_entity_name, 'ERROR', errorstring, NULL, NULL,
                       l_json_request, l_json_response);
        --halo_write_error_log (errorstring);

        -- Notify support mailbox of error
        halo_error_mail(
            p_from => l_sender,
            p_to   => l_receiver,
            p_sub  => 'Automatic error notification for Argus-HALO medicinal product configuration',
            p_body => 'This email is triggered due to an error in Argus-HALO integration for '
                      || webservice_url
                      || '. Please refer to the following error message: '
                      || l_json_request
                      || '. '
                      || sqlerrm,
            p_port => 587
        );

END HALO_TRANSFER_PRODUCT_FAMILY_CONFIG;
/

--------------------------------------------------------------
-- HALO_TRANSFER_PRODUCT_LICENSE_CONFIG
--------------------------------------------------------------
CREATE OR REPLACE PROCEDURE HALO_TRANSFER_PRODUCT_LICENSE_CONFIG (
    is_initial NUMBER DEFAULT 0
) AS

/******************************************************************************************************
--  Purpose              : Transfer product license data from Argus to the HALO configuration API
--  Input                : N/A (all License are transferred)
--  Changes:             : Created, Praveen Gupta 08-JUL-2022
						 : Issue fixing Sudarshan Hegde, 14-Sep-2022 - HLP-2289
						   Issue fixed HLP-2583 Sudarshan Hegde, 20-Oct-2022
                           : Issue Fixed: ARG-27, 14.March-2024, PK
                           : Commented IBD (International Birth Date code as it is currently not supported in HALO
******************************************************************************************************/
    l_json_request     CLOB;
    l_json_response    CLOB;
    errorstring        VARCHAR2(2000);
    webservice_url     VARCHAR2(200);
    l_sender           VARCHAR2(200);
    l_receiver         VARCHAR2(200);
    l_halo_code_source VARCHAR2(200);
    v_last_run         DATE;
    v_wallet_path      VARCHAR2(200);
    v_entity_name      VARCHAR2(100) := 'LICENSE';
    v_halo_char_id     VARCHAR2(200) := NULL;
    v_operation_type   VARCHAR(1) := '1';

  -- Added new parameters for New Authentication

    v_current_date     VARCHAR2(50 CHAR) := to_char(current_timestamp, 'DD-MON-YYYY HH24:MI:SS');
    v_auth_timestamp   VARCHAR2(50 CHAR);
    v_auth_hash_key    VARCHAR2(2000);
    v_auth_tenant_id   NUMBER;
    v_auth_secret_key  NUMBER;
    v_current_utc_time VARCHAR2(100);
    v_halo_version     NUMBER;
    l_authorization    VARCHAR2(200);   -- Authorization token

BEGIN
    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: ENTRY');
    BEGIN
        SELECT
            value
        INTO webservice_url
        FROM
            halo_config
        WHERE
            parameter = 'HALO_PRODUCT_CONFIG_WEBSERVICE';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: '
                                                   || 'Parameter for webservice URL is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

-- Added code to fetch HALO version

    BEGIN
        SELECT
            value
        INTO v_halo_version
        FROM
            halo_config
        WHERE
            parameter = 'HALO_VERSION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_VERSION: '
                                                   || 'Parameter for HALO_VERSION is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;




-- New authentication code starts from here


    IF v_halo_version = 5 THEN


-- Get the secret key
        BEGIN
            SELECT
                value
            INTO l_authorization
            FROM
                halo_config
            WHERE
                parameter = 'HALO_AUTHORIZATION';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'Parameter for api key is not configured in HALO_CONFIG');
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_timestamp
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TIMESTAMP';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_hash_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_HASH_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_tenant_id
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TENANT_ID';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_secret_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_SECRET_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        SELECT
            to_char(TO_TIMESTAMP_TZ(to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
                    'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS')
        INTO v_current_utc_time
        FROM
            dual;



  --  select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
   -- into v_current_utc_time
   -- from dual;

        IF (
            v_auth_hash_key IS NULL
            AND v_auth_timestamp IS NULL
        ) THEN
            UPDATE halo_config
            SET
                value = v_current_utc_time
            WHERE
                parameter = 'AUTH_TIMESTAMP';

            UPDATE halo_config
            SET
                value = (
                    SELECT
                        sys.dbms_crypto.hash(
                            utl_raw.cast_to_raw('TEN'
                                                || v_auth_tenant_id
                                                || ';'
                                                || v_current_utc_time
                                                || ';'
                                                || v_auth_secret_key),
                            4
                        )
                    FROM
                        dual
                )
            WHERE
                parameter = 'AUTH_HASH_KEY';

        ELSIF (
            v_auth_hash_key IS NOT NULL
            AND v_auth_timestamp IS NOT NULL
        ) THEN
            IF ( ( ( TO_DATE ( v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS' ) ) != TO_DATE ( v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'
            ) )
            OR ( TO_NUMBER ( to_char(TO_DATE(v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) < ( TO_NUMBER ( to_char(TO_DATE
            (v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) ) THEN
                UPDATE halo_config
                SET
                    value = v_current_utc_time
                WHERE
                    parameter = 'AUTH_TIMESTAMP';

                UPDATE halo_config
                SET
                    value = (
                        SELECT
                            sys.dbms_crypto.hash(
                                utl_raw.cast_to_raw('TEN'
                                                    || v_auth_tenant_id
                                                    || ';'
                                                    || v_current_utc_time
                                                    || ';'
                                                    || v_auth_secret_key),
                                4
                            )
                        FROM
                            dual
                    )
                WHERE
                    parameter = 'AUTH_HASH_KEY';

            END IF;
        END IF;

        SELECT
            value
        INTO v_auth_timestamp
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TIMESTAMP';

        SELECT
            value
        INTO v_auth_hash_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_HASH_KEY';

        SELECT
            value
        INTO v_auth_tenant_id
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TENANT_ID';

    END IF;

-- New authentication code ends here

    BEGIN
        SELECT
            CAST(from_tz(CAST(sysdate AS TIMESTAMP),(
                SELECT
                    value
                FROM
                    cmn_profile
                WHERE
                        key = 'DATABASE_TIMEZONE'
                    AND section = 'SYSTEM'
            )) AT TIME ZONE 'GMT' AS DATE)
        INTO v_current_date
        FROM
            dual;

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Unable to convert sysdate to GMT'
                                                   || sqlerrm);
		--halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for webservice URL is not configured in HALO_CONFIG'||sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_wallet_path
        FROM
            halo_config
        WHERE
            parameter = 'WALLET_PATH';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: '
                                                   || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: '
                                                   || 'Parameter for api key is not configured in HALO_CONFIG'
                                                   || sqlerrm);
    END;

    BEGIN
        SELECT
            value
        INTO l_sender
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_SENDER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: '
                                                   || 'Parameter for sender mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_receiver
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_RECEIVER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: '
                                                   || 'Parameter for receiver mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            halo_char_id
        INTO l_halo_code_source
        FROM
            stg_argus_halo_idmap
        WHERE
            entity_name = 'SOURCES';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: '
                                                   || 'Parameter for HALO_CHAR_ID is not configured in STG_ARGUS_HALO_IDMAP'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            TO_DATE(value, 'DD-MM-YYYY HH24:MI:SS')
        INTO v_last_run
        FROM
            halo_config
        WHERE
            parameter = 'LICENSES_LAST_RUN';

    EXCEPTION
        WHEN OTHERS THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: '
                                                   || 'Parameter for PHARM_FORM_LAST_RUN is not configured OR Incorrect, should in DD-MM-YYYY HH24:MI:SS format in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: VALIDATION ENTRY');
    FOR curlic IN (
        SELECT
            license_id
        FROM
            lm_license
        WHERE
            ( last_update_time >= v_last_run
              AND last_update_time <= v_current_date
              AND 1 != is_initial )
            OR ( deleted IS NULL
                 AND 1 = is_initial )
    ) LOOP
        halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: PROCESS STARTED FOR LICENSE_ID:' || curlic.license_id
        );
        v_halo_char_id := NULL;
        BEGIN
            SELECT
                halo_char_id
            INTO v_halo_char_id
            FROM
                stg_argus_halo_idmap
            WHERE
                    entity_name = v_entity_name
                AND argus_id = curlic.license_id;

        EXCEPTION
            WHEN OTHERS THEN
                v_halo_char_id := NULL;
                halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: '
                                                      || 'IS_INITIAL: '
                                                      || is_initial
                                                      || '. OPERATION_TYPE = 1 AND V_HALO_CHAR_ID IS NULL FOR ARGUS_ID:'
                                                      || curlic.license_id);

        END;

        IF ( v_halo_char_id IS NOT NULL ) THEN
            v_operation_type := '2';
        ELSE
            v_operation_type := '1';
        END IF;

        SELECT
            JSON_OBJECT(
                'HALO_message' VALUE
                    JSON_OBJECT(
                        'MPD_entities' VALUE
                            JSON_OBJECT(
                                'LICENSE' VALUE JSON_ARRAYAGG(
                                    JSON_OBJECT(
                                        'HALO_CODE' VALUE nvl2(v_halo_char_id, v_halo_char_id, ''),
                                                'OPERATION_TYPE' VALUE decode(
                                            nvl2(lic.deleted, 'Y', 'N'),
                                            'N',
                                            v_operation_type,
                                            'Y',
                                            '5'
                                        ),
                                                'APPLICATION_NUM' VALUE '',
                                                'APPLICATION_TYPE_ID' VALUE lic.app_type,
                                                'AUTH_COUNTRY_CODE' VALUE cou.a2,
                                                'AUTH_DATE' VALUE lic.award_date,
                                                'AUTH_NUM' VALUE nvl(lic.lic_number, 'UNKNOWN'),
                                                'AUTH_PROCEDURE_CODE' VALUE '',
                                                'AUTH_PROCEDURE' VALUE '',
                                                'AUTH_PROCEDURE_START_DATE' VALUE '',
                                                'AUTH_PROCEDURE_END_DATE' VALUE '',
                                                'AUTH_STATUS_CODE' VALUE '',
                                                'AUTH_JURISDICTION' VALUE '',
                                                'TRADE_NAME' VALUE lic.trade_name,
                                                'LEGAL_BASIS' VALUE '',
                                                'VALIDITY_PERIOD_START_DATE' VALUE '',
                                                'VALIDITY_PERIOD_END_DATE' VALUE '',
                                                'EXCLUSIVITY_START_DATE' VALUE '',
                                                'EXCLUSIVITY_END_DATE' VALUE '',
                                                'FIRST_AUTHORISED_DATE' VALUE '',
--                                    'INTERNATIONAL_BIRTH_DATE'		VALUE LPRO.INTL_BIRTH_DATE,
                                                'MAH_ORG_CODE' VALUE '',
                                                'MARKETING_STATUS_ID' VALUE '',
                                                'MARKETING_START_DATE' VALUE '',
                                                'MARKETING_STOP_DATE' VALUE '',
                                                'RISK_OF_SUPPLY_SHORTAGE_F' VALUE '',
                                                'RISK_OF_SUPPLY_SHORTAGE_C' VALUE '',
                                                'WITHDRAWAL_DATE' VALUE lic.withdraw_date,
                                                'SENDER_LOCAL_CODE' VALUE lic.license_id,
                                                'COMMENT' VALUE lic.comments,
                                                'MASTER_TYPE' VALUE lcty.license_type,
                                                'HALO_CODE_SOURCE' VALUE l_halo_code_source
                                    RETURNING CLOB)
                                RETURNING CLOB)
                            RETURNING CLOB)
                    RETURNING CLOB)
            RETURNING CLOB)
        INTO l_json_request
        FROM
            lm_license       lic,
--            LM_LIC_PRODUCTS LLIP,
--            LM_PRODUCT LPRO,
            lm_countries     cou,
            lm_license_types lcty
        WHERE
                lic.license_id = curlic.license_id
--            AND LIC.LICENSE_ID=LLIP.LICENSE_ID
--            AND LLIP.PRODUCT_ID=LPRO.PRODUCT_ID
            AND lic.country_id = cou.country_id (+)
            AND lic.license_type_id = lcty.license_type_id (+)
            --AND LCTY.DELETED(+) IS NULL
--            AND LPRO.DELETED IS NULL
--            AND LLIP.DELETED IS NULL
--             and ROWNUM=1
--            order by LPRO.INTL_BIRTH_DATE ;
            AND lic.deleted IS NULL
            AND cou.deleted IS NULL
            AND lcty.deleted IS NULL;

        BEGIN
            IF v_halo_version < 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;
            END IF;

            IF v_halo_version >= 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;

--  New authentication code starts here

                apex_web_service.g_request_headers(3).name := 'Tenant_ID';
                apex_web_service.g_request_headers(3).value := v_auth_tenant_id;
                apex_web_service.g_request_headers(4).name := 'Auth_Hash';
                apex_web_service.g_request_headers(4).value := v_auth_hash_key;
                apex_web_service.g_request_headers(5).name := 'Auth_Timestamp';
                apex_web_service.g_request_headers(5).value := v_auth_timestamp;

-- New authentication code ends here

            END IF;

            l_json_response := apex_web_service.make_rest_request(
                p_url         => webservice_url,
                p_http_method => 'POST',
                p_body        => l_json_request,
                p_wallet_path => v_wallet_path
            );

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: Error in loading PRODUCT License.', v_halo_char_id
                , curlic.license_id,
                               l_json_request, l_json_response);

                RETURN;
        END;

        BEGIN
            IF ( v_operation_type = '1' ) THEN
                import_halo_code_license(l_json_response, v_entity_name);
                halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: Updated to halo successfully', v_halo_char_id
                , curlic.license_id);
                halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: Response from HALO PRODUCTCONFIG endpoint'
                , v_halo_char_id, curlic.license_id,
                               l_json_request, l_json_response);

            ELSE
                halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: NO UPDATE TO STG_ARGUS_HALO_IDMAP.', v_halo_char_id
                , curlic.license_id,
                               l_json_request, l_json_response);
            END IF;
        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: Error while parsing halo response for halo and Argus ID mapping.'
                , v_halo_char_id, curlic.license_id,
                               l_json_request, l_json_response);
        END;

    END LOOP;

    halo_update_config_values('LICENSES_LAST_RUN', TO_DATE(v_current_date, 'DD-MM-YYYY HH24:MI:SS'));
    halo_write_log(v_entity_name,
                   'DEBUG',
                   'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: COMPLETED LICENSE. v_current_date' || to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'
                   ));
EXCEPTION
    WHEN OTHERS THEN
        errorstring := 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: An unexpected error occured while transferring Product License data to HALO.'
                       || substr(sqlerrm, 1, 3000)
                       || '. '
                       || dbms_utility.format_error_backtrace();

        halo_write_log(v_entity_name, 'ERROR', errorstring, NULL, NULL,
                       l_json_request, l_json_response);

        -- Notify support mailbox of error
        halo_error_mail(
            p_from => l_sender,
            p_to   => l_receiver,
            p_sub  => 'Automatic error notification for Argus-HALO medicinal product license configuration',
            p_body => 'This email is triggered due to an error in Argus-HALO integration for '
                      || webservice_url
                      || '. Please refer to the following error message: '
                      || l_json_request
                      || '. '
                      || sqlerrm,
            p_port => 587
        );

END HALO_TRANSFER_PRODUCT_LICENSE_CONFIG;
/

--------------------------------------------------------------
-- HALO_TRANSFER_SOURCE_CONFIG
--------------------------------------------------------------
CREATE OR REPLACE PROCEDURE HALO_TRANSFER_SOURCE_CONFIG AS

/******************************************************************************************************
--  Purpose              : Transfer product Source data from Argus to the HALO configuration API
--  Input                : N/A (all SOURCE are transferred)
--  Changes:             : Created, Praveen Gupta 15-July-2022

******************************************************************************************************/
    l_json_request  CLOB;
    l_json_response CLOB;
    errorstring     VARCHAR2(2000);
    webservice_url  VARCHAR2(200);
    l_sender        VARCHAR2(200);
    l_receiver      VARCHAR2(200);
    l_wallet_path   VARCHAR2(200);
    l_authorization VARCHAR2(200);
BEGIN
    halo_write_log('SOURCE', 'DEBUG', 'HALO_TRANSFER_SOURCE_CONFIG: ENTRY');
    BEGIN
        SELECT
            value
        INTO webservice_url
        FROM
            halo_config
        WHERE
            parameter = 'HALO_PRODUCT_CONFIG_WEBSERVICE';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log('SOURCE', 'ERROR', 'HALO_TRANSFER_SOURCE_CONFIG: '
                                              || 'Parameter for webservice URL is not configured in HALO_CONFIG'
                                              || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_wallet_path
        FROM
            halo_config
        WHERE
            parameter = 'WALLET_PATH';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log('SOURCE', 'ERROR', 'HALO_TRANSFER_SOURCE_CONFIG: '
                                              || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'
                                              || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log('SOURCE', 'ERROR', 'HALO_TRANSFER_SOURCE_CONFIG: '
                                              || 'Parameter for api key is not configured in HALO_CONFIG'
                                              || sqlerrm);
    END;

    BEGIN
        SELECT
            value
        INTO l_sender
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_SENDER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log('SOURCE', 'ERROR', 'HALO_TRANSFER_SOURCE_CONFIG: '
                                              || 'Parameter for sender mail is not configured in HALO_CONFIG'
                                              || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_receiver
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_RECEIVER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log('SOURCE', 'ERROR', 'HALO_TRANSFER_SOURCE_CONFIG: '
                                              || 'Parameter for receiver mail is not configured in HALO_CONFIG'
                                              || sqlerrm);
            RETURN;
    END;

    halo_write_log('SOURCE', 'DEBUG', 'HALO_TRANSFER_SOURCE_CONFIG: VALIDATION COMPLETED');
    l_json_request := '{"HALO_message": {"MPD_entities": {"SOURCE": [{"OPERATION_TYPE": "1", "TERM_TYPE_CODE": "STD","SOURCE_NAME": "ARGUS","COMMENT_SOURCE": "ARGUS","DEPRECATED_FLAG": "N","SENDER_LOCAL_CODE": "125255"}]}}}'
    ;
    BEGIN
        apex_web_service.g_request_headers.DELETE;
        apex_web_service.g_request_headers(1).name := 'Content-Type';
        apex_web_service.g_request_headers(1).value := 'application/json';
        apex_web_service.g_request_headers(2).name := 'Authorization';
        apex_web_service.g_request_headers(2).value := l_authorization;
        l_json_response := apex_web_service.make_rest_request(
            p_wallet_path => l_wallet_path,
            p_url         => webservice_url,
            p_http_method => 'POST',
            p_body        => l_json_request
        );

    EXCEPTION
        WHEN OTHERS THEN
            halo_write_log('SOURCE', 'ERROR', 'HALO_TRANSFER_SOURCE_CONFIG: Error in loading source.', NULL, NULL,
                           l_json_request, l_json_response);
            RETURN;
    END;

    BEGIN
        import_halo_code_source(l_json_response, 'SOURCES');
        halo_write_log('SOURCE', 'INFO', 'HALO_TRANSFER_SOURCE_CONFIG: Updated to halo successfully', NULL, NULL);
        halo_write_log('SOURCE', 'DEBUG', 'HALO_TRANSFER_SOURCE_CONFIG: Response from HALO PRODUCTCONFIG endpoint', NULL, NULL,
                       NULL, l_json_response);
    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log('SOURCE', 'ERROR', 'HALO_TRANSFER_SOURCE_CONFIG: Error while parsing halo response for halo and Argus ID mapping.'
            , NULL, NULL,
                           l_json_request, l_json_response);
    END;

    halo_write_log('SOURCE', 'DEBUG', 'HALO_TRANSFER_SOURCE_CONFIG: END');
EXCEPTION
    WHEN OTHERS THEN
        errorstring := 'HALO_TRANSFER_SOURCE_CONFIG: An unexpected error occured while transferring source data to HALO. '
                       || substr(sqlerrm, 1, 3000)
                       || '. '
                       || dbms_utility.format_error_backtrace();

        halo_write_log('SOURCE', 'ERROR', errorstring, NULL, NULL,
                       l_json_request, l_json_response);
        --halo_write_error_log (errorstring);

        -- Notify support mailbox of error
        halo_error_mail(
            p_from => l_sender,
            p_to   => l_receiver,
            p_sub  => 'Automatic error notification for Argus-HALO medicinal Source configuration',
            p_body => 'This email is triggered due to an error in Argus-HALO integration for '
                      || webservice_url
                      || '. Please refer to the following error message: '
                      || l_json_request
                      || '. '
                      || sqlerrm,
            p_port => 587
        );

END HALO_TRANSFER_SOURCE_CONFIG;
/

--------------------------------------------------------------
-- HALO_TRANSFER_STUDY_CONFIG
--------------------------------------------------------------

CREATE OR REPLACE PROCEDURE HALO_TRANSFER_STUDY_CONFIG
(
    is_initial NUMBER DEFAULT 0
) AS

/******************************************************************************************************
--  Purpose              : Transfer study config data from Argus to the HALO configuration API
--  Input                : N/A (all studies are transferred)
--  Changes:             : Created, Peter Stroyer Pallesen, 16-Jun-2021.
--                         Version 2 JIRA HAL-163, 2021-10-14, PSP, Updated to only send data updated on current day. Product ID added
                           Version 3, updated to make it compatible with HALO 4.02 release
******************************************************************************************************/
    l_json_request     CLOB;
    l_json_response    CLOB;
    errorstring        VARCHAR2(2000);
    webservice_url     VARCHAR2(200);
    l_sender           VARCHAR2(200);
    l_receiver         VARCHAR2(200);
    l_authorization    VARCHAR2(200);
    l_halo_code_source VARCHAR2(200);
    v_last_run         DATE;
    v_wallet_path      VARCHAR2(200);
    v_entity_name      VARCHAR2(100) := 'STUDIES';
    v_halo_char_id     VARCHAR2(200) := NULL;
    v_operation_type   VARCHAR(1) := '1';


    -- Added new parameters for New Authentication

    v_current_date     VARCHAR2(50 CHAR) := to_char(current_timestamp, 'DD-MON-YYYY HH24:MI:SS');
    v_auth_timestamp   VARCHAR2(50 CHAR);
    v_auth_hash_key    VARCHAR2(2000);
    v_auth_tenant_id   NUMBER;
    v_auth_secret_key  NUMBER;
    v_current_utc_time VARCHAR2(100);
    v_halo_version     NUMBER;
BEGIN
    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_STUDY_CONFIG: ENTRY');
    BEGIN
        SELECT
            value
        INTO webservice_url
        FROM
            halo_config
        WHERE
            parameter = 'HALO_STUDY_CONFIG_WEBSERVICE';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_STUDY_CONFIG: '
                                                   || 'Parameter for webservice URL is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;



-- Added code to fetch HALO version

    BEGIN
        SELECT
            value
        INTO v_halo_version
        FROM
            halo_config
        WHERE
            parameter = 'HALO_VERSION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_VERSION: '
                                                   || 'Parameter for HALO_VERSION is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;




-- New authentication code starts from here


    IF v_halo_version = 5 THEN


-- Get the secret key
        BEGIN
            SELECT
                value
            INTO l_authorization
            FROM
                halo_config
            WHERE
                parameter = 'HALO_AUTHORIZATION';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'Parameter for api key is not configured in HALO_CONFIG');
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_timestamp
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TIMESTAMP';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_hash_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_HASH_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_tenant_id
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TENANT_ID';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_secret_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_SECRET_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        SELECT
            to_char(TO_TIMESTAMP_TZ(to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
                    'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS')
        INTO v_current_utc_time
        FROM
            dual;



  --  select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
   -- into v_current_utc_time
   -- from dual;

        IF (
            v_auth_hash_key IS NULL
            AND v_auth_timestamp IS NULL
        ) THEN
            UPDATE halo_config
            SET
                value = v_current_utc_time
            WHERE
                parameter = 'AUTH_TIMESTAMP';

            UPDATE halo_config
            SET
                value = (
                    SELECT
                        sys.dbms_crypto.hash(
                            utl_raw.cast_to_raw('TEN'
                                                || v_auth_tenant_id
                                                || ';'
                                                || v_current_utc_time
                                                || ';'
                                                || v_auth_secret_key),
                            4
                        )
                    FROM
                        dual
                )
            WHERE
                parameter = 'AUTH_HASH_KEY';

        ELSIF (
            v_auth_hash_key IS NOT NULL
            AND v_auth_timestamp IS NOT NULL
        ) THEN
            IF ( ( ( TO_DATE ( v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS' ) ) != TO_DATE ( v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'
            ) )
            OR ( TO_NUMBER ( to_char(TO_DATE(v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) < ( TO_NUMBER ( to_char(TO_DATE
            (v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) ) THEN
                UPDATE halo_config
                SET
                    value = v_current_utc_time
                WHERE
                    parameter = 'AUTH_TIMESTAMP';

                UPDATE halo_config
                SET
                    value = (
                        SELECT
                            sys.dbms_crypto.hash(
                                utl_raw.cast_to_raw('TEN'
                                                    || v_auth_tenant_id
                                                    || ';'
                                                    || v_current_utc_time
                                                    || ';'
                                                    || v_auth_secret_key),
                                4
                            )
                        FROM
                            dual
                    )
                WHERE
                    parameter = 'AUTH_HASH_KEY';

            END IF;
        END IF;

        SELECT
            value
        INTO v_auth_timestamp
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TIMESTAMP';

        SELECT
            value
        INTO v_auth_hash_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_HASH_KEY';

        SELECT
            value
        INTO v_auth_tenant_id
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TENANT_ID';

    END IF;

-- New authentication code ends here




    BEGIN
        SELECT
            CAST(from_tz(CAST(sysdate AS TIMESTAMP),(
                SELECT
                    value
                FROM
                    cmn_profile
                WHERE
                        key = 'DATABASE_TIMEZONE'
                    AND section = 'SYSTEM'
            )) AT TIME ZONE 'GMT' AS DATE)
        INTO v_current_date
        FROM
            dual;

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Unable to convert sysdate to GMT'
                                                   || sqlerrm);
		--halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for webservice URL is not configured in HALO_CONFIG'||sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_wallet_path
        FROM
            halo_config
        WHERE
            parameter = 'WALLET_PATH';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_STUDY_CONFIG: '
                                                   || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_STUDY_CONFIG: '
                                                   || 'Parameter for api key is not configured in HALO_CONFIG'
                                                   || sqlerrm);
    END;

    BEGIN
        SELECT
            value
        INTO l_sender
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_SENDER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_STUDY_CONFIG: '
                                                   || 'Parameter for sender mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_receiver
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_RECEIVER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_STUDY_CONFIG: '
                                                   || 'Parameter for receiver mail is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            halo_char_id
        INTO l_halo_code_source
        FROM
            stg_argus_halo_idmap
        WHERE
            entity_name = 'SOURCES';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_STUDY_CONFIG: '
                                                   || 'Parameter for HALO_CHAR_ID is not configured in STG_ARGUS_HALO_IDMAP'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            TO_DATE(value, 'DD-MM-YYYY HH24:MI:SS')
        INTO v_last_run
        FROM
            halo_config
        WHERE
            parameter = 'STUDY_LAST_RUN';

    EXCEPTION
        WHEN OTHERS THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_STUDY_CONFIG: '
                                                   || 'Parameter for STUDY_LAST_RUN is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_STUDY_CONFIG: VALIDATION COMPLETED');
    FOR curstudy IN (
        SELECT
            study_key
        FROM
            lm_studies
        WHERE
            ( last_update_time >= v_last_run
              AND last_update_time <= v_current_date
              AND 1 != is_initial )
            OR ( last_update_time >= v_last_run
                 AND last_update_time <= v_current_date
                 AND deleted IS NULL
                 AND 1 = is_initial )
    ) LOOP
        halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_STUDY_CONFIG: STUDY PROCESS STARTED FOR STUDY_KEY:' || curstudy.study_key
        );
        v_halo_char_id := NULL;

  -- 1st call to transfer main study details
        SELECT
            JSON_OBJECT(
                'STUDY' VALUE JSON_ARRAYAGG(
                    JSON_OBJECT(
                        'PROTOCOL_ID' VALUE lpr.protocol_id,
                                'PROTOCOL_DESC' VALUE lpr.protocol_desc,
                                'PROTOCOL_NUM' VALUE ls.protocol_num,
                                'STUDY_KEY' VALUE ls.study_key,
                                'STUDY_DESC' VALUE replace(ls.study_desc, '''', ''''''),
                                'STUDY_NUM' VALUE ls.study_num,
                                'STUDY_ABBREV' VALUE ls.study_abbrev,
                                'OTHER_NUM' VALUE ls.other_num,
                                'UNBLIND_OK' VALUE
                            CASE ls.unblind_ok
                                WHEN 0 THEN
                                    'NO'
                                WHEN 1 THEN
                                    'YES'
                                ELSE
                                    NULL
                            END,
                                'CLASSIFICATION' VALUE(
                            SELECT
                                description
                            FROM
                                lm_case_classification
                            WHERE
                                    classification_id = ls.classification_id
                                AND deleted IS NULL
                        ),
                                'NON_INTERVENTIONAL' VALUE
                            CASE ls.non_interventional
                                WHEN 0 THEN
                                    'NO'
                                WHEN 1 THEN
                                    'YES'
                                ELSE
                                    NULL
                            END,
                                'DEV_PHASE' VALUE(
                            SELECT
                                dev_phase
                            FROM
                                lm_dev_phase
                            WHERE
                                    dev_phase_id = ls.dev_phase_id
                                AND deleted IS NULL
                        ),
                                'DELETED' VALUE decode(ls.deleted, NULL, 0, 1)
                    )
                RETURNING CLOB)
            RETURNING CLOB)
        INTO l_json_request
        FROM
            lm_protocols lpr,
            lm_studies   ls
        WHERE
                lpr.protocol_id = ls.id_protocol
            AND lpr.deleted IS NULL
            AND ls.study_key = curstudy.study_key;

        halo_write_log(v_entity_name,
                       'DEBUG',
                       'HALO_TRANSFER_STUDY_CONFIG: STUDY.',
                       NULL,
                       NULL,
                       substr(l_json_request, 1, 4000),
                       substr(l_json_response, 1, 4000));
	   --Push generated JSON to halo API for import
        BEGIN
            IF v_halo_version < 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;
            END IF;

            IF v_halo_version >= 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;

--  New authentication code starts here

                apex_web_service.g_request_headers(3).name := 'Tenant_ID';
                apex_web_service.g_request_headers(3).value := v_auth_tenant_id;
                apex_web_service.g_request_headers(4).name := 'Auth_Hash';
                apex_web_service.g_request_headers(4).value := v_auth_hash_key;
                apex_web_service.g_request_headers(5).name := 'Auth_Timestamp';
                apex_web_service.g_request_headers(5).value := v_auth_timestamp;

-- New authentication code ends here
            END IF;

            l_json_response := apex_web_service.make_rest_request(
                p_body        => l_json_request,
                p_wallet_path => v_wallet_path,
                p_url         => webservice_url,
                p_http_method => 'POST'
            );

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name,
                               'ERROR',
                               'HALO_TRANSFER_STUDY_CONFIG: Error in loading STUDY.',
                               NULL,
                               NULL,
                               substr(l_json_request, 1, 4000),
                               substr(l_json_response, 1, 4000));

                RETURN;
        END;

        halo_write_log(v_entity_name,
                       'DEBUG',
                       'HALO_TRANSFER_STUDY_CONFIG: STUDY.',
                       NULL,
                       NULL,
                       l_json_request,
                       substr(l_json_response, 1, 4000));

        halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_STUDY_CONFIG: Study json response ' || l_json_response);
        halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_STUDY_CONFIG: Study information processed for: ' || curstudy.study_key)
        ;
        halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_STUDY_CONFIG: LINKING STUDY PRODUCT PROCESS STARTED FOR STUDY_KEY: ' || curstudy.study_key
        );

    -- 2nd call to transfer study-product linking
        SELECT
            JSON_OBJECT(
                'PROD_STUDY_MAP' VALUE JSON_ARRAYAGG(
                    JSON_OBJECT(
                        'COHORT_ID' VALUE lsp.cohort_id,
                                'PRODUCT_ID' VALUE lsp.product_id,
                                'SEQ_NUM' VALUE lsp.seq_num,
                                'LICENSE_ID' VALUE lsp.license_id,
                                'BLINDED' VALUE decode(lsp.blinded, 0, 'No', 1, 'Yes'),
        -- NOT USED
        -- DECODE(LSP.PROD_TYPE_ID,1,'COMPARATOR',2,'INVESTIGATIONAL PRODUCT',3,'PLACEBO',NULL) AS PROD_TYPE,
                                'PROD_TYPE' VALUE(
                            SELECT
                                prod_type_name
                            FROM
                                cl_study_product_type cspt
                            WHERE
                                cspt.prod_type_id = lsp.prod_type_id
                        ),
                                'PRIMARY_PROD_LIC_ID' VALUE lsp.primary_product_lic_id,
                                'STUDY_KEY' VALUE lstc.study_key,
                                'STUDY_TYPE' VALUE lst.study_type,
                                'DELETED' VALUE decode(lsp.deleted, NULL, 0, 1),
                                'BLIND_NAME' VALUE replace(lstc.blind_name, '''', '''''')
                    )
                RETURNING CLOB)
            RETURNING CLOB)
        INTO l_json_request
        FROM
            lm_study_products lsp,
            lm_study_cohorts  lstc,
            lm_study_types    lst
        WHERE
                lsp.cohort_id = lstc.cohort_id
            AND lstc.study_type_id = lst.study_type_id
            AND lstc.deleted IS NULL
            AND lst.deleted IS NULL
            AND lstc.study_key = curstudy.study_key;

        halo_write_log(v_entity_name,
                       'DEBUG',
                       'HALO_TRANSFER_STUDY_CONFIG: STUDY.',
                       NULL,
                       NULL,
                       substr(l_json_request, 1, 4000),
                       substr(l_json_response, 1, 4000));
    --HALO_WRITE_LOG(v_entity_name,'DEBUG','HALO_TRANSFER_STUDY_CONFIG: PRODUCT INFORMATION PUSHED');
    --HALO_WRITE_LOG(v_entity_name,'DEBUG','HALO_TRANSFER_STUDY_CONFIG: HALO STUDYCONFIG (PRODUCTS).',NULL,NULL, l_json_request);
	--Push generated JSON to halo API for import
        BEGIN
            apex_web_service.g_request_headers.DELETE;
            apex_web_service.g_request_headers(1).name := 'Content-Type';
            apex_web_service.g_request_headers(1).value := 'application/json';
            apex_web_service.g_request_headers(2).name := 'Authorization';
            apex_web_service.g_request_headers(2).value := l_authorization;
            l_json_response := apex_web_service.make_rest_request(
                p_body        => l_json_request,
                p_wallet_path => v_wallet_path,
                p_url         => webservice_url,
                p_http_method => 'POST'
            );

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name,
                               'ERROR',
                               'HALO_TRANSFER_STUDY_CONFIG: Error in loading HALO STUDYCONFIG (PRODUCTS).',
                               NULL,
                               NULL,
                               substr(l_json_request, 1, 4000),
                               substr(l_json_response, 1, 4000));

                RETURN;
        END;

        halo_write_log(v_entity_name,
                       'ERROR',
                       'HALO_TRANSFER_STUDY_CONFIG: Error in loading HALO STUDYCONFIG (PRODUCTS).',
                       NULL,
                       NULL,
                       substr(l_json_request, 1, 4000),
                       substr(l_json_response, 1, 4000));

        halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_STUDY_CONFIG: product json response ' || l_json_response);
        halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_STUDY_CONFIG: LINKING STUDY PRODUCT PROCESS COMPLETED FOR STUDY_KEY: ' || curstudy.study_key
        );
        halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_STUDY_CONFIG: STUDY PROCESS COMPLETED FOR STUDY_KEY:' || curstudy.study_key
        );
    END LOOP;

    halo_update_config_values('STUDY_LAST_RUN',
                              to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'));
EXCEPTION
    WHEN OTHERS THEN
        errorstring := 'HALO_TRANSFER_STUDY_CONFIG: An unexpected error occured while transferring Study data to HALO. '
                       || substr(sqlerrm, 1, 3000)
                       || '. '
                       || dbms_utility.format_error_backtrace();

        halo_write_log(v_entity_name,
                       'ERROR',
                       errorstring,
                       NULL,
                       NULL,
                       substr(l_json_request, 3000),
                       substr(l_json_response, 3000));
        --halo_write_error_log (errorstring);

        -- Notify support mailbox of error
        halo_error_mail(
            p_from => l_sender,
            p_to   => l_receiver,
            p_sub  => 'Automatic error notification for Argus-HALO study configuration',
            p_body => 'This email is triggered due to an error in Argus-HALO integration for '
                      || webservice_url
                      || '. Please refer to the following error message: '
                      || l_json_request
                      || '. '
                      || sqlerrm,
            p_port => 587
        );

END;
/


--------------------------------------------------------------
-- HASH_KEY_GENERATOR
--------------------------------------------------------------

create or replace PROCEDURE HASH_KEY_GENERATOR(v_hashcode OUT VARCHAR2, v_timestamp out varchar2,v_tenant out varchar2)
as
	v_json_request CLOB;
    v_json_response CLOB;
    v_errorstring VARCHAR2(2000);
    v_current_date VARCHAR2(50 CHAR) := to_char(CURRENT_TIMESTAMP, 'DD-MON-YYYY HH24:MI:SS');
    v_auth_timestamp VARCHAR2(50 CHAR);
    v_auth_hash_key varchar2(2000);
    v_auth_tenant_id number;
    v_auth_secret_key number;
    v_entity_name varchar2(100):='ICSRS';
    v_current_utc_time varchar2(100);


BEGIN

-------------------------------
-- Initializations..
-------------------------------

    HALO_WRITE_LOG(v_entity_name,'DEBUG','HASH_KEY_GENERATOR: ENTRY');


	BEGIN
		SELECT VALUE INTO v_auth_timestamp FROM halo_config WHERE PARAMETER = 'AUTH_TIMESTAMP';
	EXCEPTION WHEN NO_DATA_FOUND THEN
        HALO_WRITE_LOG(v_entity_name,'ERROR','HASH_KEY_GENERATOR: ' || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'||sqlerrm);
		RETURN;
	END;

    BEGIN
		SELECT VALUE INTO v_auth_hash_key FROM halo_config WHERE PARAMETER = 'AUTH_HASH_KEY';
	EXCEPTION WHEN NO_DATA_FOUND THEN
        HALO_WRITE_LOG(v_entity_name,'ERROR','HASH_KEY_GENERATOR: ' || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'||sqlerrm);
		RETURN;
	END;

    BEGIN
		SELECT VALUE INTO v_auth_tenant_id FROM halo_config WHERE PARAMETER = 'AUTH_TENANT_ID';
	EXCEPTION WHEN NO_DATA_FOUND THEN
        HALO_WRITE_LOG(v_entity_name,'ERROR','HASH_KEY_GENERATOR: ' || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'||sqlerrm);
		RETURN;
	END;

    BEGIN
		SELECT VALUE INTO v_auth_secret_key FROM halo_config WHERE PARAMETER = 'AUTH_SECRET_KEY';
	EXCEPTION WHEN NO_DATA_FOUND THEN
        HALO_WRITE_LOG(v_entity_name,'ERROR','HASH_KEY_GENERATOR: ' || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'||sqlerrm);
		RETURN;
	END;


    select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
    into v_current_utc_time
    from dual;

        if(v_auth_hash_key is null and  v_auth_timestamp is null)
        then

        update halo_config
        set value =v_current_utc_time
        where PARAMETER = 'AUTH_TIMESTAMP';


        update halo_config
        set value =(SELECT SYS.DBMS_CRYPTO.HASH (UTL_RAW.CAST_TO_RAW ('TEN'||v_auth_tenant_id||';'||v_current_utc_time||';'||v_auth_secret_key), 4) FROM DUAL)
        where parameter='AUTH_HASH_KEY';


        elsif(v_auth_hash_key is not null and v_auth_timestamp is not null)
        then
            if(((TO_CHAR(TO_DATE(v_auth_timestamp,'YYYY-MM-DD"T"HH24:MI:SS'),'YYYY-MM-DD')) != (TO_CHAR(TO_DATE(v_current_utc_time,'YYYY-MM-DD"T"HH24:MI:SS'),'YYYY-MM-DD'))) OR
            (TO_NUMBER(TO_CHAR(TO_DATE(v_auth_timestamp,'YYYY-MM-DD"T"HH24:MI:SS'),'HH24')))< (TO_NUMBER(TO_CHAR(TO_DATE(v_current_utc_time,'YYYY-MM-DD"T"HH24:MI:SS'),'HH24')))
            )
            THEN
                    update halo_config
                    set value =v_current_utc_time
                    where PARAMETER = 'AUTH_TIMESTAMP';


                    update halo_config
                    set value =(SELECT SYS.DBMS_CRYPTO.HASH (UTL_RAW.CAST_TO_RAW ('TEN6;'||v_current_utc_time||';'||v_auth_secret_key), 4) FROM DUAL)
                    where parameter='AUTH_HASH_KEY';


            end if;


        END IF;

        select VALUE INTO v_timestamp from halo_config where PARAMETER = 'AUTH_TIMESTAMP';

        select VALUE INTO v_hashcode from halo_config where PARAMETER = 'AUTH_HASH_KEY';

        select VALUE INTO v_tenant from halo_config where PARAMETER = 'AUTH_TENANT_ID';

EXCEPTION
  WHEN OTHERS THEN
        v_errorstring := 'HASH_KEY_GENERATOR: An unexpected error occured while generating hash code'
                        || substr(sqlerrm, 1 , 3000)||'. '|| DBMS_UTILITY.FORMAT_ERROR_BACKTRACE();
        HALO_WRITE_LOG(v_entity_name,'ERROR',v_errorstring,NULL,NULL,v_json_request, v_json_response );

							 -- Notify support mailbox of error
          /*halo_error_mail
          (
            p_from => v_sender,
            p_to  => v_receiver,
            p_sub  => 'Automatic error notification for Argus-HALO icsr data integration configuration (pulling data into Argus)',
												p_body => 'This email is triggered due to an error in Argus-HALO integration for ' || v_webservice_url_icsr ||'. Please refer to the following error message: ' || v_json_request || '. ' || sqlerrm,
            p_port => 587
          );  */
END;
/


--------------------------------------------------------------
-- HALO_TRANSFER_SUBSTANCE_CONFIG
--------------------------------------------------------------

CREATE OR REPLACE PROCEDURE HALO_TRANSFER_SUBSTANCE_CONFIG (
    is_initial NUMBER DEFAULT 0
) AS

/******************************************************************************************************
--  Purpose              : Transfer product substances data from Argus to the HALO configuration API
--  Input                : N/A (all products are transferred)
--  Changes:             : Created, Praveen Gupta, 08-JUL-2022
******************************************************************************************************/
    l_json_request     CLOB;
    l_json_response    CLOB;
    errorstring        VARCHAR2(2000);
    webservice_url     VARCHAR2(200);
    l_sender           VARCHAR2(200);
    l_receiver         VARCHAR2(200);
    l_authorization    VARCHAR2(200);
    l_halo_code_source VARCHAR2(200);
    v_current_date     DATE := to_char(current_timestamp, 'DD-MON-YYYY HH24:MI:SS');
    v_last_run         DATE;
    v_wallet_path      VARCHAR2(200);
    v_entity_name      VARCHAR2(100) := 'SUBSTANCES';
    v_halo_char_id     VARCHAR2(200) := NULL;
    v_operation_type   VARCHAR(1) := '1';


    -- Added new parameters for New Authentication

    v_auth_timestamp   VARCHAR2(50 CHAR);
    v_auth_hash_key    VARCHAR2(2000);
    v_auth_tenant_id   NUMBER;
    v_auth_secret_key  NUMBER;
    v_current_utc_time VARCHAR2(100);
    v_halo_version     NUMBER;
BEGIN
    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_SUBSTANCE_CONFIG: ENTRY');
    BEGIN
        SELECT
            value
        INTO webservice_url
        FROM
            halo_config
        WHERE
            parameter = 'HALO_PRODUCT_CONFIG_WEBSERVICE';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_SUBSTANCE_CONFIG: '
                                                   || 'Parameter for webservice URL is not configured in HALO_CONFIG. '
                                                   || sqlerrm);
        --halo_write_error_log ('ERROR: HALO_TRANSFER_SUBSTANCE_CONFIG: ' || 'Parameter for webservice URL is not configured in HALO_CONFIG' || sqlerrm);
            RETURN;
    END;



-- Added code to fetch HALO version

    BEGIN
        SELECT
            value
        INTO v_halo_version
        FROM
            halo_config
        WHERE
            parameter = 'HALO_VERSION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_VERSION: '
                                                   || 'Parameter for HALO_VERSION is not configured in halo_config'
                                                   || sqlerrm);
            RETURN;
    END;




-- New authentication code starts from here


    IF v_halo_version = 5 THEN


-- Get the secret key
        BEGIN
            SELECT
                value
            INTO l_authorization
            FROM
                halo_config
            WHERE
                parameter = 'HALO_AUTHORIZATION';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'Parameter for api key is not configured in HALO_CONFIG');
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_timestamp
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TIMESTAMP';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TIMESTAMP is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_hash_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_HASH_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_HASH_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_tenant_id
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_TENANT_ID';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_TENANT_ID is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        BEGIN
            SELECT
                value
            INTO v_auth_secret_key
            FROM
                halo_config
            WHERE
                parameter = 'AUTH_SECRET_KEY';

        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HASH_KEY_GENERATOR: '
                                                       || 'Parameter for AUTH_SECRET_KEY is not configured in halo_config'
                                                       || sqlerrm);
                RETURN;
        END;

        SELECT
            to_char(TO_TIMESTAMP_TZ(to_char(current_timestamp, 'YYYY-MM-DD HH24:MI:SS'),
                    'YYYY-MM-DD HH24:MI:SS') AT TIME ZONE 'UTC',
                    'YYYY-MM-DD"T"HH24:MI:SS')
        INTO v_current_utc_time
        FROM
            dual;



  --  select TO_CHAR (TO_TIMESTAMP_TZ (cast(current_timestamp as timestamp) at time zone 'UTC', 'DD-MM-RR HH.MI.SS.FF9 AM TZR'),'YYYY-MM-DD"T"HH24:MI:SS')
   -- into v_current_utc_time
   -- from dual;

        IF (
            v_auth_hash_key IS NULL
            AND v_auth_timestamp IS NULL
        ) THEN
            UPDATE halo_config
            SET
                value = v_current_utc_time
            WHERE
                parameter = 'AUTH_TIMESTAMP';

            UPDATE halo_config
            SET
                value = (
                    SELECT
                        sys.dbms_crypto.hash(
                            utl_raw.cast_to_raw('TEN'
                                                || v_auth_tenant_id
                                                || ';'
                                                || v_current_utc_time
                                                || ';'
                                                || v_auth_secret_key),
                            4
                        )
                    FROM
                        dual
                )
            WHERE
                parameter = 'AUTH_HASH_KEY';

        ELSIF (
            v_auth_hash_key IS NOT NULL
            AND v_auth_timestamp IS NOT NULL
        ) THEN
            IF ( ( ( TO_DATE ( v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS' ) ) != TO_DATE ( v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'
            ) )
            OR ( TO_NUMBER ( to_char(TO_DATE(v_auth_timestamp, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) < ( TO_NUMBER ( to_char(TO_DATE
            (v_current_utc_time, 'YYYY-MM-DD"T"HH24:MI:SS'), 'HH24') ) ) ) THEN
                UPDATE halo_config
                SET
                    value = v_current_utc_time
                WHERE
                    parameter = 'AUTH_TIMESTAMP';

                UPDATE halo_config
                SET
                    value = (
                        SELECT
                            sys.dbms_crypto.hash(
                                utl_raw.cast_to_raw('TEN'
                                                    || v_auth_tenant_id
                                                    || ';'
                                                    || v_current_utc_time
                                                    || ';'
                                                    || v_auth_secret_key),
                                4
                            )
                        FROM
                            dual
                    )
                WHERE
                    parameter = 'AUTH_HASH_KEY';

            END IF;
        END IF;

        SELECT
            value
        INTO v_auth_timestamp
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TIMESTAMP';

        SELECT
            value
        INTO v_auth_hash_key
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_HASH_KEY';

        SELECT
            value
        INTO v_auth_tenant_id
        FROM
            halo_config
        WHERE
            parameter = 'AUTH_TENANT_ID';

    END IF;

-- New authentication code ends here




    BEGIN
        SELECT
            CAST(from_tz(CAST(sysdate AS TIMESTAMP),(
                SELECT
                    value
                FROM
                    cmn_profile
                WHERE
                        key = 'DATABASE_TIMEZONE'
                    AND section = 'SYSTEM'
            )) AT TIME ZONE 'GMT' AS DATE)
        INTO v_current_date
        FROM
            dual;

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_MED_PRODUCT_CONFIG: '
                                                   || 'Unable to convert sysdate to GMT'
                                                   || sqlerrm);
		--halo_write_error_log ('ERROR: HALO_TRANSFER_MED_PRODUCT_CONFIG: ' || 'Parameter for webservice URL is not configured in HALO_CONFIG'||sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO v_wallet_path
        FROM
            halo_config
        WHERE
            parameter = 'WALLET_PATH';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_SUBSTANCE_CONFIG: '
                                                   || 'Parameter for Wallet PATH is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_sender
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_SENDER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_SUBSTANCE_CONFIG: '
                                                   || 'Parameter for sender mail is not configured in HALO_CONFIG. '
                                                   || sqlerrm);
        --halo_write_error_log ('ERROR: HALO_TRANSFER_SUBSTANCE_CONFIG: ' || 'Parameter for sender mail is not configured in HALO_CONFIG'|| sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_receiver
        FROM
            halo_config
        WHERE
            parameter = 'HALO_ERROR_MAIL_RECEIVER';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_SUBSTANCE_CONFIG: '
                                                   || 'Parameter for receiver mail is not configured in HALO_CONFIG. '
                                                   || sqlerrm);
        --halo_write_error_log ('ERROR: HALO_TRANSFER_SUBSTANCE_CONFIG: ' || 'Parameter for receiver mail is not configured in HALO_CONFIG'|| sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            halo_char_id
        INTO l_halo_code_source
        FROM
            stg_argus_halo_idmap
        WHERE
            entity_name = 'SOURCES';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_SUBSTANCE_CONFIG: '
                                                   || 'Parameter for HALO_CHAR_ID is not configured in STG_ARGUS_HALO_IDMAP. '
                                                   || sqlerrm);
        --halo_write_error_log ('ERROR: HALO_TRANSFER_SUBSTANCE_CONFIG: ' || 'Parameter for HALO_CHAR_ID is not configured in STG_ARGUS_HALO_IDMAP'||sqlerrm);
            RETURN;
    END;

    BEGIN
        SELECT
            value
        INTO l_authorization
        FROM
            halo_config
        WHERE
            parameter = 'HALO_AUTHORIZATION';

    EXCEPTION
        WHEN no_data_found THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_SUBSTANCE_CONFIG: '
                                                   || 'Parameter for api key is not configured in HALO_CONFIG. '
                                                   || sqlerrm);
        --halo_write_error_log ('ERROR: HALO_TRANSFER_SUBSTANCE_CONFIG: ' || 'Parameter for api key is not configured in HALO_CONFIG'|| sqlerrm);
    END;

    BEGIN
        SELECT
            TO_DATE(value, 'DD-MM-YYYY HH24:MI:SS')
        INTO v_last_run
        FROM
            halo_config
        WHERE
            parameter = 'SUBSTANCE_LAST_RUN';

    EXCEPTION
        WHEN OTHERS THEN
            halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_SUBSTANCE_CONFIG: '
                                                   || 'Parameter for SUBSTANCE_LAST_RUN is not configured in HALO_CONFIG'
                                                   || sqlerrm);
            RETURN;
    END;

    halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_SUBSTANCE_CONFIG: VALIDATION COMPLETE');
    FOR cursubs IN (
        SELECT
            ingredient_id
        FROM
            lm_ingredients
        WHERE
            ( last_update_time >= v_last_run
              AND last_update_time <= v_current_date
              AND 1 != is_initial )
            OR ( deleted IS NULL
                 AND 1 = is_initial )
        ORDER BY
            ingredient_id ASC
    ) LOOP
        halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_SUBSTANCE_CONFIG: PROCESSING FOR curSUBS.INGREDIENT_ID:' || cursubs.ingredient_id
        );
        v_halo_char_id := NULL;
        BEGIN
            SELECT
                halo_char_id
            INTO v_halo_char_id
            FROM
                stg_argus_halo_idmap
            WHERE
                    entity_name = v_entity_name
                AND argus_id = cursubs.ingredient_id;

        EXCEPTION
            WHEN OTHERS THEN
                v_halo_char_id := NULL;
                halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_SUBSTANCE_CONFIG: '
                                                      || 'IS_INITIAL: '
                                                      || is_initial
                                                      || '. OPERATION_TYPE = 1 AND V_HALO_CHAR_ID IS NULL FOR ARGUS_ID:'
                                                      || cursubs.ingredient_id);

        END;

        IF ( v_halo_char_id IS NOT NULL ) THEN
            v_operation_type := '2';
        ELSE
            v_operation_type := '1';
        END IF;

        SELECT
            JSON_OBJECT(
                'HALO_message' VALUE
                    JSON_OBJECT(
                        'MPD_entities' VALUE
                            JSON_OBJECT(
                                'SUBSTANCE' VALUE JSON_ARRAYAGG(
                                    JSON_OBJECT(
                                        'HALO_CODE' VALUE nvl2(v_halo_char_id, v_halo_char_id, ''),
                                                'OPERATION_TYPE' VALUE decode(
                                            nvl2(lmi.deleted, 'Y', 'N'),
                                            'N',
                                            v_operation_type,
                                            'Y',
                                            '5'
                                        ),
                                                'COMMENT_SUBSTANCE' VALUE lmi.ingredient_j,
                                                'SUBSTANCE_PREFERRED_NAME' VALUE lmi.ingredient,
                                                'DEPRECATED_FLAG' VALUE nvl2(lmi.deleted, 'Y', 'N'),
                                                'SENDER_LOCAL_CODE' VALUE lmi.ingredient_id,
                                                'HALO_CODE_SOURCE' VALUE l_halo_code_source,
                                                'TERM_TYPE_CODE' VALUE 'STD'
                                    RETURNING CLOB)
                                RETURNING CLOB)
                            RETURNING CLOB)
                    RETURNING CLOB)
            RETURNING CLOB)
        INTO l_json_request
        FROM
            lm_ingredients lmi
        WHERE
            lmi.ingredient_id = cursubs.ingredient_id;


        --INSERT INTO TEMP(JSONT,ID) VALUES(l_json_request,211);
        BEGIN
            IF v_halo_version < 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;
            END IF;

            IF v_halo_version >= 5 THEN
                apex_web_service.g_request_headers.DELETE;
                apex_web_service.g_request_headers(1).name := 'Content-Type';
                apex_web_service.g_request_headers(1).value := 'application/json';
                apex_web_service.g_request_headers(2).name := 'Authorization';
                apex_web_service.g_request_headers(2).value := l_authorization;

--  New authentication code starts here

                apex_web_service.g_request_headers(3).name := 'Tenant_ID';
                apex_web_service.g_request_headers(3).value := v_auth_tenant_id;
                apex_web_service.g_request_headers(4).name := 'Auth_Hash';
                apex_web_service.g_request_headers(4).value := v_auth_hash_key;
                apex_web_service.g_request_headers(5).name := 'Auth_Timestamp';
                apex_web_service.g_request_headers(5).value := v_auth_timestamp;

-- New authentication code ends here

            END IF;

            l_json_response := apex_web_service.make_rest_request(
                p_wallet_path => v_wallet_path,
                p_url         => webservice_url,
                p_http_method => 'POST',
                p_body        => l_json_request
            );
            --INSERT INTO TEMP(JSONT,ID) VALUES(l_json_response,212);
        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_SUBSTANCE_CONFIG: Error in loading SUBSTANCE.', v_halo_char_id,
                cursubs.ingredient_id,
                               l_json_request, l_json_response);
            --halo_write_error_log ('INFO: HALO_TRANSFER_SUBSTANCE_CONFIG: Error in loading substance: ' || curSUBS.INGREDIENT_ID || substr(l_json_response, 1, 4000));
        END;

        BEGIN
            IF ( v_operation_type = '1' ) THEN
                import_halo_code_substance(l_json_response, v_entity_name);
                halo_write_log(v_entity_name, 'INFO', 'HALO_TRANSFER_SUBSTANCE_CONFIG: Updated to halo successfully', v_halo_char_id,
                cursubs.ingredient_id);
                halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_SUBSTANCE_CONFIG: Response from HALO SUBSTANCECONFIG endpoint',
                v_halo_char_id, cursubs.ingredient_id,
                               l_json_request, l_json_response);

            ELSE
                halo_write_log(v_entity_name, 'DEBUG', 'HALO_TRANSFER_PRODUCT_LICENSE_CONFIG: NO UPDATE TO STG_ARGUS_HALO_IDMAP.', v_halo_char_id
                , cursubs.ingredient_id,
                               l_json_request, l_json_response);
            END IF;
        EXCEPTION
            WHEN no_data_found THEN
                halo_write_log(v_entity_name, 'ERROR', 'HALO_TRANSFER_SUBSTANCE_CONFIG: Error while parsing halo response for halo and Argus ID mapping.'
                , v_halo_char_id, cursubs.ingredient_id,
                               l_json_request, l_json_response);
            --halo_write_error_log ('ERROR: HALO_TRANSFER_SUBSTANCE_CONFIG: ' || curSUBS.INGREDIENT_ID || ' Unable to parse halo API response for Argus and HALO Substance ID map.');
                RETURN;
        END;

    END LOOP;

    halo_update_config_values('SUBSTANCE_LAST_RUN',
                              to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'));
    halo_write_log(v_entity_name,
                   'DEBUG',
                   'HALO_TRANSFER_SUBSTANCE_CONFIG: COMPLETED SUBSTANCE. v_current_date' || to_char(v_current_date, 'DD-MM-YYYY HH24:MI:SS'
                   ));
EXCEPTION
    WHEN OTHERS THEN
        errorstring := 'ERROR: HALO_TRANSFER_PRODUCT_SUBSTANCE_CONFIG: An unexpected error occured while transferring Argus Substance data to HALO. '
                       || substr(sqlerrm, 1, 3000)
                       || '. '
                       || dbms_utility.format_error_backtrace();

        halo_write_log('PRODUCTS', 'ERROR', errorstring, NULL, NULL,
                       l_json_request, l_json_response);
        --halo_write_error_log (sqlerrm);

		-- Notify support mailbox of error
        halo_error_mail(
            p_from => l_sender,
            p_to   => l_receiver,
            p_sub  => 'Automatic error notification for Argus-HALO substance configuration',
            p_body => 'This email is triggered due to an error in Argus-HALO integration for '
                      || webservice_url
                      || '. Please refer to the following error message: '
                      || l_json_request
                      || '. '
                      || sqlerrm,
            p_port => 587
        );

END HALO_TRANSFER_SUBSTANCE_CONFIG;
/

--------------------------------------------------------------
-- HALO_ICSR_DATA_TRANSFER_JOB
--------------------------------------------------------------

CREATE OR REPLACE PROCEDURE HALO_ICSR_DATA_TRANSFER_JOB AS
/******************************************************************************************************
-- File Name: JOB_TRANSFER_ICSR_DATA.SQL
-- Purpose: This procedure is responsible for transferring Argus ICSR data to HALO. It checks for recently updated cases in Argus and transfers them to HALO using a RESTful web service.
-- Revisions:
--   Revision 1, 22-06-2022 PSP: Header created (object added in CIL for source control).
--   Revision 2, 19-09-2023 ED: Allows exclusion of case transfer based on case_classifications, based on a parameter in HALO_CONFIG.
--   Revision 3, 12-10-2023 DD: Converted into a Job procedure. Modified to add p_out_status variable to handle JSON response. CSL error.
--   Revision 4, 16-01-2023 DD: Converted the ICSR Run time to Parameter - ICSR_INTERVAL
--   Revision 5, 26-04-2024 PK: Added code to restrict case transfer of Clinical Trial cases
-- 	 Revision 6, 18-06-2024 DD: Arg-54- Include case classification
--   Revision 7, 06-05-2026 Divin: CHG0162228
--	 Revision 8, 25-06-2026 PSP: Added update of halo_transfer_attachment (Halo 6.x)
******************************************************************************************************/

    v_query          VARCHAR2(1000);        -- SQL query for database operations
    v_count          NUMBER;                 -- General-purpose numeric variable
    l_case_present   NUMBER;                 -- Indicates if a case is already present in the migration table
    l_aer_no         NUMBER;                 -- Numeric variable for AER (Adverse Event Report) number
    l_version_number NUMBER;                -- Numeric variable for version numbers
    l_transfer_case  NUMBER;                 -- Indicates if a case should be transferred
    p_out_status     NUMBER;                 -- Status variable to handle JSON response
    v_entity_name    VARCHAR2(30) := 'halo_icsr_data_transfer_job';  -- Entity name for logging



    -- Search for cases updated in the last 6 hours
    CURSOR v_case_cursor IS
    SELECT
        cm.case_num,
        cm.case_id,
        cm.last_update_time,
        cm.state_id
    FROM
        case_master cm
    WHERE
            cm.last_update_time >= sysdate - numtodsinterval((
                SELECT
                    value
                FROM
                    halo_config
                WHERE
                    parameter LIKE 'ICSR_INTERVAL'
            ), 'HOUR')
    -- Explicitly ensure the case has at least one classification
        AND EXISTS (
            SELECT
                1
            FROM
                case_classifications cc
            WHERE
                cc.case_id = cm.case_id
        )
    -- Include only cases with CSL Behring classification
        AND EXISTS (
            SELECT
                1
            FROM
                     case_classifications cc_i
                JOIN lm_case_classification lm_i ON lm_i.classification_id = cc_i.classification_id
            WHERE
                    cc_i.case_id = cm.case_id
                AND lm_i.description IN (
                    SELECT
                        value
                    FROM
                        halo_config
                    WHERE
                        parameter = 'ICSR_DATA_TRANSFER_INCLUDE_ARGUS_CLASSIFICATIONS'
                )
        )
    MINUS
    SELECT
        cm.case_num,
        cm.case_id,
        cm.last_update_time,
        cm.state_id
    FROM
        case_master cm
    WHERE
            cm.last_update_time >= sysdate - numtodsinterval((
                SELECT
                    value
                FROM
                    halo_config
                WHERE
                    parameter LIKE 'ICSR_INTERVAL'
            ), 'HOUR')
        AND EXISTS (
            SELECT
                1
            FROM
                case_study cs
            WHERE
                    cs.case_id = cm.case_id
                AND cs.classification_id = (
                    SELECT
                        classification_id
                    FROM
                        lm_case_classification
                    WHERE
                        upper(description) IN (
                            SELECT
                                upper(value)
                            FROM
                                halo_config
                            WHERE
                                parameter = 'ICSR_DATA_TRANSFER_EXCLUDE_ARGUS_O_STUDY_TYPE'
                        )
                )
        );

BEGIN
    halo_write_log(v_entity_name, 'INFO', 'Scheduler started looking for cases to tansfer to HALO');
    -- start the loop to iterate through the cases
    FOR i IN v_case_cursor LOOP
        p_out_status := 0;
        -- Verify if the case is already transferred
        SELECT
            COUNT(1)
        INTO l_transfer_case
        FROM
            halo_migrated_cases hmc
        WHERE
                i.case_id = hmc.case_id
            AND i.last_update_time = hmc.last_tranfer_time
            AND hmc.status = 1;

        IF l_transfer_case = 0 THEN
            SELECT
                COUNT(1)
            INTO l_case_present
            FROM
                halo_migrated_cases hmc
            WHERE
                i.case_id = hmc.case_id;

-- Make an entry if case is not trasferred yet
            IF l_case_present = 0 THEN
                INSERT INTO halo_migrated_cases (
                    case_id,
                    last_tranfer_time,
                    status
                ) VALUES ( i.case_id,
                           i.last_update_time,
                           0 );

            ELSE
                UPDATE halo_migrated_cases
                SET
                    status = 0
                WHERE
                    case_id = i.case_id;

            END IF;

            halo_write_log(v_entity_name, 'INFO', 'Transfer Job initiated for case : ' || i.case_num);
    -- Procedure call to Transfer data using restful webservice
            halo_icsr_r3_data_transfer(i.case_num, i.state_id, p_out_status);

            --Update the status to 1 if the case is transferred sucessfully
            IF p_out_status = 1 THEN
                UPDATE halo_migrated_cases
                SET
                    last_tranfer_time = i.last_update_time,
                    status = 1
                WHERE
                    case_id = i.case_id;

				UPDATE halo_transfer_attachment
                SET
                    status = 1
                WHERE
                    case_id = i.case_id;
            END IF;

            halo_write_log(v_entity_name, 'INFO', 'Transfer Job COMPLETED for case : ' || i.case_num);
            COMMIT;
        END IF;

    END LOOP;

EXCEPTION
    WHEN OTHERS THEN
        halo_write_log(v_entity_name, 'ERROR', 'JOB_TRANSFER_ICSR_DATA: ' || sqlerrm);
END;
/

create or replace FUNCTION                   "GET_C11" (
    pi_case_id NUMBER
) RETURN VARCHAR2 IS
/******************************************************************************************************
-- Purpose              : Generate C_1_1 value
-- Input                : case_id
-- Changes              : Created, Dheeraj Dhawan, 16-Nov-2023
                        V1.1 SB - Changed Error Handling 
******************************************************************************************************/
    l_companynumb        VARCHAR2(100);
    v_case_num           VARCHAR2(100);
    v_company_identifier VARCHAR2(200);
BEGIN
    l_companynumb := NULL;

    -- Retrieve the case number based on the input case_id
    SELECT
        case_num
    INTO v_case_num
    FROM
        case_master
    WHERE
        case_id = pi_case_id;

    -- Determine the company identifier based on unique company names in regulatory contacts


    SELECT
        CASE
            WHEN COUNT(DISTINCT upper(cont_company_name)) = 1 THEN
                MAX(upper(cont_company_name))
            ELSE
                (
                    SELECT
                        upper(value)
                    FROM
                        halo_config
                    WHERE
                        parameter = 'COMPANY_IDENTIFIER'
                )
        END
    INTO v_company_identifier
    FROM
        lm_regulatory_contact
    WHERE
        cont_company_name IS NOT NULL
    GROUP BY
        upper(cont_company_name);

    -- Construct the final company number using specified format
    SELECT
        upper(lc.a2
              || '-'
              || v_company_identifier
              || '-'
              || cm.case_num)
    INTO l_companynumb
    FROM
        lm_countries lc,
        case_master  cm,
        (
            SELECT
                case_id,
                country_id
            FROM
                (
                    SELECT
                        case_id,
                        CASE
                            WHEN country_id > 0 THEN
                                country_id
                            ELSE
                                NULL
                        END    country_id,
                        primary_contact,
                        COUNT(1)
                        OVER() rcount
                    FROM
                        case_reporters
                    WHERE
                            case_id = pi_case_id
                        AND deleted IS NULL
                )
            WHERE
                primary_contact = 1
                OR rcount = 1
        )            cr
    WHERE
            cm.case_id = pi_case_id
        AND cm.case_id = cr.case_id (+)
        AND lc.country_id = nvl(cr.country_id, cm.country_id);

    RETURN l_companynumb;
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -1422 THEN
            RETURN v_case_num;
        END IF;

        halo_write_log(
            'GET_C11',
            'ERROR',
            'GET_C11'
            || 'Could not generate c11: '
            || SQLERRM
            || CHR(13)
            || CHR(10)
            || DBMS_UTILITY.format_error_backtrace()
        );

        RETURN v_case_num;
END get_c11;
/

--------------------------------------------------------------
-- Compile!
--------------------------------------------------------------
BEGIN
    DBMS_UTILITY.COMPILE_SCHEMA(
        schema => 'HALO_STAGE',
        compile_all => FALSE
    );
END;
/

