CLASS lcl_buffer DEFINITION.
  PUBLIC SECTION.
    CLASS-DATA: mt_jentry_post    TYPE TABLE FOR ACTION IMPORT i_journalentrytp~post,
                mt_key_post       TYPE zfi_i_period_record,
                mt_mapped_post    TYPE RESPONSE FOR MAPPED i_journalentrytp,
                mt_jentry_reverse TYPE TABLE FOR ACTION IMPORT i_journalentrytp~reverse,
                mt_key_reverse    TYPE zfi_i_period_record,
                mt_mapped_reverse TYPE RESPONSE FOR MAPPED i_journalentrytp.
ENDCLASS.

CLASS lcl_buffer IMPLEMENTATION.

ENDCLASS.

CLASS lhc_periodrecord DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR periodrecord RESULT result.

    METHODS read FOR READ
      IMPORTING keys FOR READ periodrecord RESULT result.

    METHODS lock FOR LOCK
      IMPORTING keys FOR LOCK periodrecord.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR periodrecord RESULT result.

    METHODS accounting FOR MODIFY
      IMPORTING keys FOR ACTION periodrecord~accounting.

    METHODS reverse FOR MODIFY
      IMPORTING keys FOR ACTION periodrecord~reverse.

ENDCLASS.

CLASS lhc_periodrecord IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD read.
  ENDMETHOD.

  METHOD lock.
  ENDMETHOD.

  METHOD get_instance_features.
    CHECK keys IS NOT INITIAL.

    SELECT * FROM zfi_t_period_s
      FOR ALL ENTRIES IN @keys
      WHERE header_uuid        = @keys-headeruuid AND
            header_object_type = @keys-headerobjecttype AND
            item_uuid          = @keys-itemuuid AND
            simulate_uuid      = @keys-simulateuuid
       INTO TABLE @DATA(lt_simulate).

    result =
      VALUE #(
        FOR ls_simulate IN lt_simulate
          LET is_accountable = COND #( WHEN ls_simulate-simulate_comp = abap_false
                                         THEN if_abap_behv=>fc-o-enabled
                                         ELSE if_abap_behv=>fc-o-disabled  )
              is_reversable  = COND #( WHEN ls_simulate-simulate_comp = abap_true
                                         THEN if_abap_behv=>fc-o-enabled
                                         ELSE if_abap_behv=>fc-o-disabled  )
          IN
            ( %tky-headerobjecttype = ls_simulate-header_object_type
              %tky-headeruuid       = ls_simulate-header_uuid
              %tky-itemuuid         = ls_simulate-item_uuid
              %tky-simulateuuid     = ls_simulate-simulate_uuid
              %tky-keydate          = keys[ 1 ]-keydate
              %action-accounting    = is_accountable
              %action-reverse       = is_reversable
             ) ).
  ENDMETHOD.

  METHOD accounting.

    DATA: lt_jentry TYPE TABLE FOR ACTION IMPORT i_journalentrytp~post,
          ls_jentry LIKE LINE OF lt_jentry,
          ls_glitem LIKE LINE OF ls_jentry-%param-_glitems,
          ls_amount LIKE LINE OF ls_glitem-_currencyamount.

    CHECK keys IS NOT INITIAL.

    DATA(ls_key) = keys[ 1 ].

    SELECT a~headeruuid, a~objectnumber, a~companycode, a~headertext,
           a~headerobjecttype, b~itemuuid, b~mainaccount, b~documenttype,
           b~vehicleflag, b~ntdeaccount, b~rateflag,
           b~wbselement , b~costaccount, b~itemobjecttype, c~simulateuuid,
           b~costcenter, c~endshowdate, c~periodamount, c~currencycode, c~ncamount,
           c~documentnumber, c~documentyear,c~simulatecomp, c~simulatevalid
      FROM zfi_i_period_h AS a
      INNER JOIN zfi_i_period_i AS b ON b~headeruuid       = a~headeruuid AND
                                        b~headerobjecttype = a~headerobjecttype
      INNER JOIN zfi_i_period_s AS c ON c~headeruuid       = b~headeruuid AND
                                        c~headerobjecttype = b~headerobjecttype AND
                                        c~itemuuid         = b~itemuuid
      WHERE a~headerobjecttype = @ls_key-headerobjecttype AND
            a~headeruuid       = @ls_key-headeruuid AND
            b~itemuuid         = @ls_key-itemuuid
        INTO TABLE @DATA(lt_data).

    READ TABLE lt_data INTO DATA(ls_data) WITH KEY simulateuuid = ls_key-simulateuuid.

    CHECK sy-subrc = 0.

    TRY.
        cl_abap_datfm=>conv_date_int_to_ext(
          EXPORTING im_datint    = ls_data-endshowdate
                    im_datfmdes  = '1'
          IMPORTING ex_datext    = DATA(lv_date_string)
                    ex_datfmused = DATA(lv_date_format) ).
      CATCH cx_abap_datfm_format_unknown.
    ENDTRY.

    IF ls_data-simulatecomp = abap_true.
      APPEND VALUE #(  %msg   = new_message( id       = 'ZFI_PERIOD_MSG'
                                             number   = 019
                                             severity = if_abap_behv_message=>severity-error
                                             v1       = lv_date_string
                                             v2       = ls_data-objectnumber
                                             v3       = ls_data-itemobjecttype )
                                           ) TO reported-periodrecord.
      RETURN.
    ENDIF.

    IF ls_data-simulatevalid = abap_true.
      APPEND VALUE #(  %msg   = new_message( id       = 'ZFI_PERIOD_MSG'
                                             number   = 020
                                             severity = if_abap_behv_message=>severity-error
                                             v1       = lv_date_string
                                             v2       = ls_data-objectnumber
                                             v3       = ls_data-itemobjecttype )
                                           ) TO reported-periodrecord.
      RETURN.
    ENDIF.

    SORT lt_data BY endshowdate ASCENDING.

    LOOP AT lt_data INTO DATA(ls_previous_data) WHERE endshowdate < ls_data-endshowdate AND
                                                      simulatecomp = abap_false.
      EXIT.
    ENDLOOP.

    IF sy-subrc = 0.
      APPEND VALUE #(  %msg   = new_message( id       = 'ZFI_PERIOD_MSG'
                                             number   = 022
                                             severity = if_abap_behv_message=>severity-error
                                             v1       = lv_date_string
                                             v2       = ls_data-objectnumber
                                             v3       = ls_data-itemobjecttype )
                                           ) TO reported-periodrecord.
      RETURN.
    ENDIF.


    ls_jentry-%cid = 'cid_header'.
    ls_jentry-%param = VALUE #(  companycode                  = ls_data-companycode
                                 businesstransactiontype      = 'RFBU'
                                 accountingdocumenttype       = ls_data-documenttype
                                 accountingdocumentheadertext = ls_data-objectnumber
                                 createdbyuser                = cl_abap_context_info=>get_user_technical_name(  )
                                 documentdate                 = ls_key-keydate
                                 postingdate                  = ls_key-keydate ).

    CLEAR ls_glitem.

    ls_glitem = VALUE #( glaccountlineitem = '001'
                         glaccount         = ls_data-mainaccount
                         documentitemtext  = ls_data-headertext ).

    APPEND VALUE #( currencyrole = '00'
                    currency     = ls_data-currencycode
                    journalentryitemamount = ls_data-periodamount * -1 ) TO ls_glitem-_currencyamount.

    DATA(lv_journalentryitemamount_main) = ls_glitem-_currencyamount[ 1 ]-journalentryitemamount.
    lv_journalentryitemamount_main = lv_journalentryitemamount_main * -1.

    IF ls_data-rateflag = abap_true.
      APPEND VALUE #( currencyrole = '10'
                      currency     = 'TRY'
                      journalentryitemamount = ls_data-ncamount * -1 ) TO ls_glitem-_currencyamount.

      DATA(lv_journalentry_main_try) = ls_glitem-_currencyamount[ 2 ]-journalentryitemamount.
      lv_journalentry_main_try = lv_journalentry_main_try * -1.
    ENDIF.

    APPEND ls_glitem TO ls_jentry-%param-_glitems.

    IF ls_data-vehicleflag = abap_false.
      CLEAR ls_glitem.

      ls_glitem = VALUE #( glaccountlineitem = '002'
                           glaccount         = ls_data-costaccount
                           costcenter        = ls_data-costcenter
                           documentitemtext  = ls_data-headertext
                           wbselement        = ls_data-wbselement ).

      APPEND VALUE #( currencyrole = '00'
                      currency     = ls_data-currencycode
                      journalentryitemamount = ls_data-periodamount ) TO ls_glitem-_currencyamount.

      IF ls_data-rateflag = abap_true.
        APPEND VALUE #( currencyrole = '10'
                        currency     = 'TRY'
                        journalentryitemamount = ls_data-ncamount  ) TO ls_glitem-_currencyamount.
      ENDIF.

      APPEND ls_glitem TO ls_jentry-%param-_glitems.
    ELSE.
      CLEAR ls_glitem.

      ls_glitem = VALUE #( glaccountlineitem = '002'
                           glaccount         = ls_data-costaccount
                           costcenter        = ls_data-costcenter
                           documentitemtext  = ls_data-headertext
                           wbselement        = ls_data-wbselement ).

      APPEND VALUE #( currencyrole = '00'
                      currency     = ls_data-currencycode
                      journalentryitemamount = ls_data-periodamount * 70 / 100 ) TO ls_glitem-_currencyamount.


      DATA(lv_journalentryitemamount_sum) = ls_glitem-_currencyamount[ 1 ]-journalentryitemamount.

      IF ls_data-rateflag = abap_true.
        APPEND VALUE #( currencyrole = '10'
                        currency     = 'TRY'
                        journalentryitemamount = ls_data-ncamount * 70 / 100 ) TO ls_glitem-_currencyamount.

        DATA(lv_journalentryitemamount_try) = ls_glitem-_currencyamount[ 2 ]-journalentryitemamount.
      ENDIF.

      APPEND ls_glitem TO ls_jentry-%param-_glitems.


      CLEAR ls_glitem.

      ls_glitem = VALUE #( glaccountlineitem = '003'
                           glaccount         = ls_data-ntdeaccount
"                           costcenter        = ls_data-costcenter
                           documentitemtext  = ls_data-headertext
                           wbselement        = ls_data-wbselement ).

      ls_glitem-_profitabilitysupplement-CostCenter = ls_data-costcenter.
      ls_glitem-_profitabilitysupplement-ProfitCenter = '0000001000'.

      APPEND VALUE #( currencyrole = '00'
                      currency     = ls_data-currencycode
                      journalentryitemamount = ls_data-periodamount * 30 / 100 ) TO ls_glitem-_currencyamount.

      lv_journalentryitemamount_sum = lv_journalentryitemamount_sum + ls_glitem-_currencyamount[ 1 ]-journalentryitemamount.

      IF ls_data-rateflag = abap_true.
        APPEND VALUE #( currencyrole = '10'
                        currency     = 'TRY'
                        journalentryitemamount = ls_data-ncamount * 30 / 100 ) TO ls_glitem-_currencyamount.

        lv_journalentryitemamount_try = lv_journalentryitemamount_try + ls_glitem-_currencyamount[ 2 ]-journalentryitemamount.
      ENDIF.

      IF lv_journalentryitemamount_sum NE lv_journalentryitemamount_main.
        DATA(lv_difference) = CONV wrbtr( lv_journalentryitemamount_sum - lv_journalentryitemamount_main ).
        ls_glitem-_currencyamount[ 1 ]-journalentryitemamount = ls_glitem-_currencyamount[ 1 ]-journalentryitemamount - lv_difference.
      ENDIF.

      IF ls_data-rateflag = abap_true.
        IF lv_journalentryitemamount_try NE lv_journalentry_main_try.
          lv_difference = lv_journalentryitemamount_try - lv_journalentry_main_try .
          ls_glitem-_currencyamount[ 2 ]-journalentryitemamount = ls_glitem-_currencyamount[ 2 ]-journalentryitemamount - lv_difference.
        ENDIF.
      ENDIF.

      APPEND ls_glitem TO ls_jentry-%param-_glitems.
    ENDIF.

    APPEND ls_jentry TO lt_jentry.
    lcl_buffer=>mt_jentry_post = lt_jentry.
    lcl_buffer=>mt_key_post = CORRESPONDING #( ls_key ).
  ENDMETHOD.

  METHOD reverse.
    DATA: lt_jreverse TYPE TABLE FOR ACTION IMPORT i_journalentrytp~reverse.

    CHECK keys IS NOT INITIAL.

    DATA(ls_key) = keys[ 1 ].

    SELECT a~headeruuid, a~objectnumber, a~companycode, a~headertext,
           a~headerobjecttype, b~itemuuid, b~mainaccount, b~documenttype,
           b~wbselement , b~costaccount, b~itemobjecttype, c~simulateuuid,
           b~costcenter, c~endshowdate, c~periodamount, c~currencycode,
           c~documentnumber, c~documentyear,c~simulatecomp, c~simulatevalid
      FROM zfi_i_period_h AS a
      INNER JOIN zfi_i_period_i AS b ON b~headeruuid       = a~headeruuid AND
                                        b~headerobjecttype = a~headerobjecttype
      INNER JOIN zfi_i_period_s AS c ON c~headeruuid       = b~headeruuid AND
                                        c~headerobjecttype = b~headerobjecttype AND
                                        c~itemuuid         = b~itemuuid
      WHERE a~headerobjecttype = @ls_key-headerobjecttype AND
            a~headeruuid       = @ls_key-headeruuid AND
            b~itemuuid         = @ls_key-itemuuid
        INTO TABLE @DATA(lt_data).

    READ TABLE lt_data INTO DATA(ls_data) WITH KEY simulateuuid = ls_key-simulateuuid.

    CHECK sy-subrc = 0.

    TRY.
        cl_abap_datfm=>conv_date_int_to_ext(
          EXPORTING im_datint    = ls_data-endshowdate
                    im_datfmdes  = '1'
          IMPORTING ex_datext    = DATA(lv_date_string)
                    ex_datfmused = DATA(lv_date_format) ).
      CATCH cx_abap_datfm_format_unknown.
    ENDTRY.

    IF ls_data-simulatecomp = abap_false.
      APPEND VALUE #(  %msg   = new_message( id       = 'ZFI_PERIOD_MSG'
                                             number   = 023
                                             severity = if_abap_behv_message=>severity-error
                                             v1       = lv_date_string
                                             v2       = ls_data-objectnumber
                                             v3       = ls_data-itemobjecttype )
                                           ) TO reported-periodrecord.
      RETURN.
    ENDIF.

    IF ls_data-simulatevalid = abap_true.
      APPEND VALUE #(  %msg   = new_message( id       = 'ZFI_PERIOD_MSG'
                                             number   = 020
                                             severity = if_abap_behv_message=>severity-error
                                             v1       = lv_date_string
                                             v2       = ls_data-objectnumber
                                             v3       = ls_data-itemobjecttype )
                                           ) TO reported-periodrecord.
      RETURN.
    ENDIF.

    SORT lt_data BY endshowdate ASCENDING.

    LOOP AT lt_data INTO DATA(ls_previous_data) WHERE endshowdate > ls_data-endshowdate AND
                                                      simulatecomp = abap_true.
      EXIT.
    ENDLOOP.

    IF sy-subrc = 0.
      APPEND VALUE #(  %msg   = new_message( id       = 'ZFI_PERIOD_MSG'
                                             number   = 024
                                             severity = if_abap_behv_message=>severity-error
                                             v1       = lv_date_string
                                             v2       = ls_data-objectnumber
                                             v3       = ls_data-itemobjecttype )
                                           ) TO reported-periodrecord.
      RETURN.
    ENDIF.

    SELECT SINGLE postingdate FROM i_journalentry
      WHERE accountingdocument = @ls_data-documentnumber AND
            fiscalyear = @ls_data-documentyear AND
            companycode = @ls_data-companycode
      INTO @DATA(lv_postingdate).

    APPEND INITIAL LINE TO lt_jreverse ASSIGNING FIELD-SYMBOL(<ls_jr>).
    <ls_jr>-companycode = ls_data-companycode.
    <ls_jr>-fiscalyear = ls_data-documentyear.
    <ls_jr>-accountingdocument = ls_data-documentnumber.
    <ls_jr>-%param = VALUE #( postingdate = lv_postingdate
                              reversalreason = '01'
                              createdbyuser = cl_abap_context_info=>get_user_technical_name(  ) ).

    lcl_buffer=>mt_jentry_reverse = lt_jreverse.
    lcl_buffer=>mt_key_reverse = CORRESPONDING #( ls_key ).
  ENDMETHOD.

ENDCLASS.

CLASS lsc_zfi_i_period_record DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.

    METHODS finalize REDEFINITION.

    METHODS check_before_save REDEFINITION.

    METHODS save REDEFINITION.

    METHODS cleanup REDEFINITION.

    METHODS cleanup_finalize REDEFINITION.

ENDCLASS.

CLASS lsc_zfi_i_period_record IMPLEMENTATION.

  METHOD finalize.
    IF lcl_buffer=>mt_jentry_post IS NOT INITIAL.
      MODIFY ENTITIES OF i_journalentrytp
            ENTITY journalentry
           EXECUTE post
              FROM lcl_buffer=>mt_jentry_post
            MAPPED DATA(ls_mapped)
            FAILED DATA(ls_failed)
          REPORTED DATA(ls_reported).

      IF ls_failed IS INITIAL.
        lcl_buffer=>mt_mapped_post-journalentry = ls_mapped-journalentry.
      ELSE.
        LOOP AT ls_reported-journalentry INTO DATA(ls_reported_journalentry).
          APPEND VALUE #(  %msg             = ls_reported_journalentry-%msg
                           %state_area      = 'JOURNAL_POST'
                           headeruuid       = lcl_buffer=>mt_key_post-headeruuid
                           itemuuid         = lcl_buffer=>mt_key_post-itemuuid
                           simulateuuid     = lcl_buffer=>mt_key_post-simulateuuid
                           headerobjecttype = lcl_buffer=>mt_key_post-headerobjecttype
                           keydate          = lcl_buffer=>mt_key_post-keydate )
            TO reported-periodrecord.
        ENDLOOP.
      ENDIF.
    ENDIF.

    IF lcl_buffer=>mt_jentry_reverse IS NOT INITIAL.
      MODIFY ENTITIES OF i_journalentrytp PRIVILEGED
      ENTITY journalentry
      EXECUTE reverse FROM lcl_buffer=>mt_jentry_reverse
      FAILED ls_failed
      REPORTED ls_reported
      MAPPED ls_mapped.
      IF ls_failed IS INITIAL.
        lcl_buffer=>mt_mapped_reverse-journalentry = ls_mapped-journalentry.
      ELSE.
        LOOP AT ls_reported-journalentry INTO ls_reported_journalentry.
          APPEND VALUE #(  %msg             = ls_reported_journalentry-%msg
                           %state_area      = 'JOURNAL_REVERSE'
                           headeruuid       = lcl_buffer=>mt_key_reverse-headeruuid
                           itemuuid         = lcl_buffer=>mt_key_reverse-itemuuid
                           simulateuuid     = lcl_buffer=>mt_key_reverse-simulateuuid
                           headerobjecttype = lcl_buffer=>mt_key_reverse-headerobjecttype
                           keydate          = lcl_buffer=>mt_key_reverse-keydate )
            TO reported-periodrecord.
        ENDLOOP.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD check_before_save.
  ENDMETHOD.

  METHOD save.
    IF lcl_buffer=>mt_mapped_post IS NOT INITIAL.
      LOOP AT lcl_buffer=>mt_mapped_post-journalentry INTO DATA(ls_mapped_journalentry).
        CONVERT KEY OF i_journalentrytp FROM ls_mapped_journalentry-%pid TO DATA(ls_key).

        SELECT SINGLE * FROM zfi_t_period_i
          WHERE header_uuid        = @lcl_buffer=>mt_key_post-headeruuid AND
                item_uuid          = @lcl_buffer=>mt_key_post-itemuuid AND
                header_object_type = @lcl_buffer=>mt_key_post-headerobjecttype
          INTO @DATA(ls_period_item).

        SELECT * FROM zfi_t_period_s
          WHERE header_uuid        = @lcl_buffer=>mt_key_post-headeruuid AND
                item_uuid          = @lcl_buffer=>mt_key_post-itemuuid AND
                header_object_type = @lcl_buffer=>mt_key_post-headerobjecttype
          INTO TABLE @DATA(lt_period_upd).

        READ TABLE lt_period_upd INTO DATA(ls_period_self) WITH KEY header_uuid        = lcl_buffer=>mt_key_post-headeruuid
                                                                   item_uuid          = lcl_buffer=>mt_key_post-itemuuid
                                                                   header_object_type = lcl_buffer=>mt_key_post-headerobjecttype
                                                                   simulate_uuid      = lcl_buffer=>mt_key_post-simulateuuid.
        IF ls_period_self-nc_flag = abap_false.
          IF ls_period_item-rate_flag = abap_true.
            SELECT SINGLE *
              FROM zfi_i_period_curr_conv( p_amount      = @ls_period_self-period_amount,
                                           p_source_curr = @ls_period_self-currency_code,
                                           p_target_curr = 'TRY',
                                           p_ratetype    = 'M',
                                           p_date        = @ls_period_item-start_date )
              INTO @DATA(ls_cur_conv).
            DATA(lv_cur_self) = ls_cur_conv-convertedamount.
            DATA(lv_calc_date) = ls_period_item-start_date.
          ELSE.
            SELECT SINGLE *
              FROM zfi_i_period_curr_conv( p_amount      = @ls_period_self-period_amount,
                                           p_source_curr = @ls_period_self-currency_code,
                                           p_target_curr = 'TRY',
                                           p_ratetype    = 'M',
                                           p_date        = @ls_period_self-end_show_date )
              INTO @ls_cur_conv.
            lv_cur_self  = ls_cur_conv-convertedamount.
            lv_calc_date = ls_period_self-end_show_date.
          ENDIF.
        ELSE.
          lv_cur_self = ls_period_self-period_amount.
        ENDIF.

        MODIFY lt_period_upd FROM VALUE #( document_number = ls_key-accountingdocument
                                           document_year   = ls_key-fiscalyear
                                           simulate_comp   = abap_true )
          TRANSPORTING document_number document_year simulate_comp
          WHERE simulate_uuid = lcl_buffer=>mt_key_post-simulateuuid AND
                item_uuid   = lcl_buffer=>mt_key_post-itemuuid AND
                header_uuid = lcl_buffer=>mt_key_post-headeruuid AND
                header_object_type = lcl_buffer=>mt_key_post-headerobjecttype.

        READ TABLE lt_period_upd INTO DATA(ls_period_upd) WITH KEY simulate_comp = abap_false.
        IF sy-subrc = 0.
          UPDATE zfi_t_period_i
            SET item_status = 'DEV'
             WHERE header_uuid        = @lcl_buffer=>mt_key_post-headeruuid AND
                   item_uuid          = @lcl_buffer=>mt_key_post-itemuuid AND
                   header_object_type = @lcl_buffer=>mt_key_post-headerobjecttype.
        ELSE.
          UPDATE zfi_t_period_i
            SET item_status = 'TAM'
             WHERE header_uuid        = @lcl_buffer=>mt_key_post-headeruuid AND
                   item_uuid          = @lcl_buffer=>mt_key_post-itemuuid AND
                   header_object_type = @lcl_buffer=>mt_key_post-headerobjecttype.

          SELECT * FROM zfi_t_period_i
            WHERE header_uuid        = @lcl_buffer=>mt_key_post-headeruuid AND
                  header_object_type = @lcl_buffer=>mt_key_post-headerobjecttype
            INTO TABLE @DATA(lt_period_item_upd).

          MODIFY lt_period_item_upd FROM VALUE #( item_status = 'TAM' )
            TRANSPORTING item_status
            WHERE item_uuid   = lcl_buffer=>mt_key_post-itemuuid AND
                  header_uuid = lcl_buffer=>mt_key_post-headeruuid AND
                  header_object_type = lcl_buffer=>mt_key_post-headerobjecttype.

          LOOP AT lt_period_item_upd INTO DATA(ls_period_item_upd) WHERE item_status <> 'TAM'.
            EXIT.
          ENDLOOP.
          IF sy-subrc <> 0.
            UPDATE zfi_t_period_h
              SET status = 'TAM'
               WHERE header_uuid        = @lcl_buffer=>mt_key_post-headeruuid AND
                     header_object_type = @lcl_buffer=>mt_key_post-headerobjecttype.
          ENDIF.
        ENDIF.

        UPDATE zfi_t_period_s
          SET document_number = @ls_key-accountingdocument,
              document_year   = @ls_key-fiscalyear,
              simulate_comp   = @abap_true,
              nc_amount       = @lv_cur_self
           WHERE header_uuid        = @lcl_buffer=>mt_key_post-headeruuid AND
                 item_uuid          = @lcl_buffer=>mt_key_post-itemuuid AND
                 simulate_uuid      = @lcl_buffer=>mt_key_post-simulateuuid AND
                 header_object_type = @lcl_buffer=>mt_key_post-headerobjecttype.

        IF ls_period_self-nc_flag = abap_false.
          LOOP AT lt_period_upd ASSIGNING FIELD-SYMBOL(<fs_period_up>) WHERE simulate_uuid <> lcl_buffer=>mt_key_post-simulateuuid AND
                                                                             simulate_comp = abap_false.
            SELECT SINGLE *
              FROM zfi_i_period_curr_conv( p_amount      = @<fs_period_up>-period_amount,
                                           p_source_curr = @<fs_period_up>-currency_code,
                                           p_target_curr = 'TRY',
                                           p_ratetype    = 'M',
                                           p_date        = @lv_calc_date )
              INTO @ls_cur_conv.

            UPDATE zfi_t_period_s
              SET nc_amount = @ls_cur_conv-convertedamount
               WHERE header_uuid        = @<fs_period_up>-header_uuid AND
                     item_uuid          = @<fs_period_up>-item_uuid AND
                     simulate_uuid      = @<fs_period_up>-simulate_uuid AND
                     header_object_type = @<fs_period_up>-header_object_type.
          ENDLOOP.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF lcl_buffer=>mt_mapped_reverse IS NOT INITIAL.
      LOOP AT lcl_buffer=>mt_mapped_reverse-journalentry INTO ls_mapped_journalentry.
        CONVERT KEY OF i_journalentrytp FROM ls_mapped_journalentry-%pid TO ls_key.

        SELECT SINGLE * FROM zfi_t_period_i
          WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
                item_uuid          = @lcl_buffer=>mt_key_reverse-itemuuid AND
                header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype
          INTO @ls_period_item.

        SELECT * FROM zfi_t_period_s
          WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
                item_uuid          = @lcl_buffer=>mt_key_reverse-itemuuid AND
                header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype
          INTO TABLE @lt_period_upd.

        READ TABLE lt_period_upd INTO ls_period_self WITH KEY header_uuid        = lcl_buffer=>mt_key_reverse-headeruuid
                                                              item_uuid          = lcl_buffer=>mt_key_reverse-itemuuid
                                                              header_object_type = lcl_buffer=>mt_key_reverse-headerobjecttype
                                                              simulate_uuid      = lcl_buffer=>mt_key_reverse-simulateuuid.

        SORT lt_period_upd BY end_show_date DESCENDING.

        IF ls_period_self-nc_flag = abap_false.
          LOOP AT lt_period_upd INTO DATA(ls_period_prev) WHERE end_show_date < ls_period_self-end_show_date AND
                                                                simulate_comp = abap_true.
            EXIT.
          ENDLOOP.
          IF sy-subrc = 0.
            IF ls_period_item-rate_flag = abap_true.
              SELECT SINGLE *
                FROM zfi_i_period_curr_conv( p_amount      = @ls_period_self-period_amount,
                                             p_source_curr = @ls_period_self-currency_code,
                                             p_target_curr = 'TRY',
                                             p_ratetype    = 'M',
                                             p_date        = @ls_period_item-start_date )
                INTO @DATA(ls_cur_prev_conv).
              DATA(lv_cur_prev) = ls_cur_prev_conv-convertedamount.
              lv_calc_date = ls_period_item-start_date.
            ELSE.
              SELECT SINGLE *
                FROM zfi_i_period_curr_conv( p_amount      = @ls_period_self-period_amount,
                                             p_source_curr = @ls_period_self-currency_code,
                                             p_target_curr = 'TRY',
                                             p_ratetype    = 'M',
                                             p_date        = @ls_period_prev-end_show_date )
                INTO @ls_cur_prev_conv.
              lv_cur_prev = ls_cur_prev_conv-convertedamount.
              lv_calc_date = ls_period_prev-end_show_date.
            ENDIF.
          ELSE.
            SELECT SINGLE *
              FROM zfi_i_period_curr_conv( p_amount      = @ls_period_self-period_amount,
                                           p_source_curr = @ls_period_self-currency_code,
                                           p_target_curr = 'TRY',
                                           p_ratetype    = 'M',
                                           p_date        = @ls_period_item-start_date )
              INTO @ls_cur_prev_conv.

            lv_cur_prev = ls_cur_prev_conv-convertedamount.
            lv_calc_date = ls_period_item-start_date.
          ENDIF.
        ELSE.
          lv_cur_prev = ls_period_prev-period_amount.
        ENDIF.

        MODIFY lt_period_upd FROM VALUE #( document_number = space
                                           document_year   = space
                                           simulate_comp   = abap_false )
          TRANSPORTING document_number document_year simulate_comp
          WHERE simulate_uuid = lcl_buffer=>mt_key_reverse-simulateuuid AND
                item_uuid   = lcl_buffer=>mt_key_reverse-itemuuid AND
                header_uuid = lcl_buffer=>mt_key_reverse-headeruuid AND
                header_object_type = lcl_buffer=>mt_key_reverse-headerobjecttype.

        READ TABLE lt_period_upd INTO ls_period_upd WITH KEY simulate_comp = abap_true.
        IF sy-subrc = 0.
          UPDATE zfi_t_period_i
            SET item_status = 'DEV'
             WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
                   item_uuid          = @lcl_buffer=>mt_key_reverse-itemuuid AND
                   header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype.

          UPDATE zfi_t_period_h
            SET status = 'BAS'
             WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
                   header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype.
        ELSE.
          UPDATE zfi_t_period_i
            SET item_status = 'YRT'
             WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
                   item_uuid          = @lcl_buffer=>mt_key_reverse-itemuuid AND
                   header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype.

          SELECT * FROM zfi_t_period_i
            WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
                  header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype
            INTO TABLE @lt_period_item_upd.

          MODIFY lt_period_item_upd FROM VALUE #( item_status = 'YRT' )
            TRANSPORTING item_status
            WHERE item_uuid   = lcl_buffer=>mt_key_reverse-itemuuid AND
                  header_uuid = lcl_buffer=>mt_key_reverse-headeruuid AND
                  header_object_type = lcl_buffer=>mt_key_reverse-headerobjecttype.

          LOOP AT lt_period_item_upd INTO ls_period_item_upd WHERE item_status <> 'YRT'.
            EXIT.
          ENDLOOP.
          IF sy-subrc <> 0.
            UPDATE zfi_t_period_h
              SET status = 'BAS'
               WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
                     header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype.
          ENDIF.
        ENDIF.

        UPDATE zfi_t_period_s
          SET document_number = @space,
              document_year   = @space,
              simulate_comp   = @abap_false,
              nc_amount       = @lv_cur_prev
           WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
                 item_uuid          = @lcl_buffer=>mt_key_reverse-itemuuid AND
                 simulate_uuid      = @lcl_buffer=>mt_key_reverse-simulateuuid AND
                 header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype.

        IF ls_period_self-nc_flag = abap_false.
          LOOP AT lt_period_upd ASSIGNING <fs_period_up> WHERE simulate_uuid <> lcl_buffer=>mt_key_reverse-simulateuuid AND
                                                               simulate_comp = abap_false.
            SELECT SINGLE *
              FROM zfi_i_period_curr_conv( p_amount      = @<fs_period_up>-period_amount,
                                           p_source_curr = @<fs_period_up>-currency_code,
                                           p_target_curr = 'TRY',
                                           p_ratetype    = 'M',
                                           p_date        = @lv_calc_date )
              INTO @ls_cur_conv.

            UPDATE zfi_t_period_s
              SET nc_amount       = @ls_cur_conv-convertedamount
               WHERE header_uuid        = @<fs_period_up>-header_uuid AND
                     item_uuid          = @<fs_period_up>-item_uuid AND
                     simulate_uuid      = @<fs_period_up>-simulate_uuid AND
                     header_object_type = @<fs_period_up>-header_object_type.
          ENDLOOP.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD cleanup.
  ENDMETHOD.

  METHOD cleanup_finalize.
  ENDMETHOD.

ENDCLASS.
