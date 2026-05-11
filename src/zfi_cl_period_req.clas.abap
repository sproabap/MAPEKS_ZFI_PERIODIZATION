CLASS zfi_cl_period_req DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_rap_query_provider .

    METHODS: get_period_data IMPORTING io_request TYPE REF TO if_rap_query_request
                             EXPORTING ev_line    TYPE int8
                             CHANGING  ct_data    TYPE ANY TABLE.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZFI_CL_PERIOD_REQ IMPLEMENTATION.


  METHOD get_period_data.
    DATA(top)               = CONV i( io_request->get_paging( )->get_page_size( ) ).
    DATA(skip)              = CONV i( io_request->get_paging( )->get_offset( ) ).
    DATA(requested_fields)  = io_request->get_requested_elements( ).
    DATA(sort_order)        = io_request->get_sort_elements( ).
    TRY.
        DATA(user_lang)         = cl_abap_context_info=>get_user_language_abap_format(  ).
      CATCH cx_abap_context_info_error.
    ENDTRY.

    TRY.
        DATA(conditions) = io_request->get_filter( )->get_as_ranges(  ).
      CATCH cx_rap_query_filter_no_range.
    ENDTRY.

    DATA: lt_record           TYPE STANDARD TABLE OF zfi_i_period_record WITH EMPTY KEY,
          lr_objectnumber     TYPE RANGE OF zfi_i_period_record-objectnumber,
          lr_headerobjecttype TYPE RANGE OF zfi_i_period_record-headerobjecttype,
          lr_itemobjecttype   TYPE RANGE OF zfi_i_period_record-itemobjecttype,
          lr_companycode      TYPE RANGE OF zfi_i_period_record-companycode,
          lr_accounted        TYPE RANGE OF zfi_i_period_record-accounted,
          lr_simulateuuid     TYPE RANGE OF zfi_i_period_record-simulateuuid,
          lr_itemuuid         TYPE RANGE OF zfi_i_period_record-itemuuid,
          lr_headeruuid       TYPE RANGE OF zfi_i_period_record-headeruuid.

    LOOP AT conditions INTO DATA(condition).
      CASE condition-name.
        WHEN 'OBJECTNUMBER'.
          MOVE-CORRESPONDING condition-range TO lr_objectnumber.
        WHEN 'HEADEROBJECTTYPE'.
          MOVE-CORRESPONDING condition-range TO lr_headerobjecttype.
        WHEN 'ITEMOBJECTTYPE'.
          MOVE-CORRESPONDING condition-range TO lr_itemobjecttype.
        WHEN 'COMPANYCODE'.
          MOVE-CORRESPONDING condition-range TO lr_companycode.
        WHEN 'ENDSHOWDATE'.
          DATA(lv_keydate) = condition-range[ 1 ]-low.
        WHEN 'ACCOUNTED'.
          MOVE-CORRESPONDING condition-range TO lr_accounted.
        WHEN 'SIMULATEUUID'.
          DATA(lv_object_page) = abap_true.
          MOVE-CORRESPONDING condition-range TO lr_simulateuuid.
        WHEN 'ITEMUUID'.
          MOVE-CORRESPONDING condition-range TO lr_itemuuid.
        WHEN 'HEADERUUID'.
          MOVE-CORRESPONDING condition-range TO lr_headeruuid.
      ENDCASE.
    ENDLOOP.

    IF lv_object_page = abap_true.
      SELECT a~headeruuid, a~objectnumber, a~companycode,
             a~headerobjecttype, b~itemuuid, b~mainaccount,
             b~costaccount, b~itemobjecttype, c~simulateuuid,
             c~endshowdate, c~periodamount, c~currencycode,
             c~documentnumber, c~documentyear,c~simulatecomp, c~simulatevalid
        FROM zfi_i_period_h AS a
        INNER JOIN zfi_i_period_i AS b ON b~headeruuid       = a~headeruuid AND
                                          b~headerobjecttype = a~headerobjecttype
        INNER JOIN zfi_i_period_s AS c ON c~headeruuid       = b~headeruuid AND
                                          c~headerobjecttype = b~headerobjecttype AND
                                          c~itemuuid         = b~itemuuid
        WHERE a~status           NE 'ASK' AND
              a~status           NE 'IPT' AND
              a~headerobjecttype IN @lr_headerobjecttype AND
              a~headeruuid       IN @lr_headeruuid AND
              b~itemuuid         IN @lr_itemuuid AND
              c~simulateuuid     IN @lr_simulateuuid
          INTO CORRESPONDING FIELDS OF TABLE @lt_record.
    ELSE.
      SELECT a~headeruuid, a~objectnumber, a~companycode,
             a~headerobjecttype, b~itemuuid, b~mainaccount,
             b~costaccount, b~itemobjecttype, c~simulateuuid,
             c~endshowdate, c~periodamount, c~currencycode,
             c~documentnumber, c~documentyear,c~simulatecomp, c~simulatevalid
        FROM zfi_i_period_h AS a
        INNER JOIN zfi_i_period_i AS b ON b~headeruuid       = a~headeruuid AND
                                          b~headerobjecttype = a~headerobjecttype
        INNER JOIN zfi_i_period_s AS c ON c~headeruuid       = b~headeruuid AND
                                          c~headerobjecttype = b~headerobjecttype AND
                                          c~itemuuid         = b~itemuuid
        WHERE a~status           NE 'ASK' AND
              a~status           NE 'IPT' AND
              a~objectnumber     IN @lr_objectnumber AND
              a~headerobjecttype IN @lr_headerobjecttype AND
              a~companycode      IN @lr_companycode AND
              b~itemobjecttype   IN @lr_itemobjecttype AND
              c~endshowdate      LE @lv_keydate AND
              c~simulatecomp     IN @lr_accounted
          INTO CORRESPONDING FIELDS OF TABLE @lt_record.
    ENDIF.

    LOOP AT lt_record ASSIGNING FIELD-SYMBOL(<fs_record>).
      <fs_record>-keydate    = lv_keydate.

      TRY.
          cl_abap_datfm=>conv_date_int_to_ext(
            EXPORTING im_datint    = <fs_record>-endshowdate
                      im_datfmdes  = '1'
            IMPORTING ex_datext    = DATA(lv_date_string)
                      ex_datfmused = DATA(lv_date_format) ).
        CATCH cx_abap_datfm_format_unknown.
      ENDTRY.

      <fs_record>-identifier = |{ <fs_record>-objectnumber }/{ <fs_record>-itemobjecttype }/Dönem: { lv_date_string }|.
    ENDLOOP.

    IF lr_accounted IS INITIAL.
      SORT lt_record BY objectnumber ASCENDING
                        endshowdate ASCENDING.

    ELSE.
      IF lr_accounted[ 1 ]-low = abap_true.
        SORT lt_record BY objectnumber ASCENDING
                          endshowdate DESCENDING.
      ELSE.
        SORT lt_record BY objectnumber ASCENDING
                          endshowdate ASCENDING.
      ENDIF.
    ENDIF.

    ev_line = lines( lt_record ).

    IF top >= 0.
      IF skip EQ 0.
        DELETE lt_record FROM top + 1.
      ELSE.
        DELETE lt_record FROM top + skip + 1 TO lines( lt_record ).
        DELETE lt_record FROM 1 TO skip.
      ENDIF.
    ENDIF.

    ct_data = lt_record.
  ENDMETHOD.


  METHOD if_rap_query_provider~select.
    "    IF io_request->is_data_requested( ).
    CASE io_request->get_entity_id( ).
      WHEN 'ZFI_I_PERIOD_RECORD'.
        DATA: lt_record TYPE STANDARD TABLE OF zfi_i_period_record WITH EMPTY KEY.
        get_period_data( EXPORTING io_request = io_request
                         IMPORTING ev_line    = DATA(lv_line)
                         CHANGING  ct_data    = lt_record ).
        io_response->set_total_number_of_records( lv_line ).
        io_response->set_data( lt_record ).
    ENDCASE.
    "    ENDIF.
  ENDMETHOD.
ENDCLASS.
