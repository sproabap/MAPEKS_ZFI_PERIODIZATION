CLASS lcl_buffer DEFINITION.
  PUBLIC SECTION.
    CLASS-DATA: mt_header_log_create TYPE STANDARD TABLE OF zfi_t_period_h,
                mt_header_log_update TYPE STANDARD TABLE OF zfi_t_period_h,
                mt_item_log_create   TYPE STANDARD TABLE OF zfi_t_period_i,
                mt_item_log_update   TYPE STANDARD TABLE OF zfi_t_period_i.

    CLASS-DATA: mt_buf_sim_cre TYPE TABLE OF zfi_t_period_s,
                mt_buf_sim_del TYPE TABLE OF zfi_t_period_s.

    CLASS-DATA mt_mapped_reverse  TYPE RESPONSE FOR MAPPED i_journalentrytp.
    CLASS-DATA mt_key_reverse     TYPE zfi_i_period_s.
    CLASS-DATA mt_key_bill        TYPE zfi_i_period_s.
    CLASS-DATA mt_jentry_bill     TYPE TABLE FOR ACTION IMPORT i_journalentrytp~post.
    CLASS-DATA mt_mapped_bill     TYPE RESPONSE FOR MAPPED i_journalentrytp.
    CLASS-DATA mt_bill_reverse    TYPE TABLE FOR ACTION IMPORT i_journalentrytp~reverse.
    CLASS-DATA mt_key_bill_rev    TYPE zfi_i_period_i.
    CLASS-DATA mt_mapped_rev_bill TYPE RESPONSE FOR MAPPED i_journalentrytp.

    CLASS-METHODS simulate_all IMPORTING is_item TYPE zfi_t_period_i.
ENDCLASS.

CLASS lcl_buffer IMPLEMENTATION.

  METHOD simulate_all.
    DATA: BEGIN OF ls_period,
            period_no        TYPE i,
            start_calc_date  TYPE datum,
            start_show_date  TYPE datum,
            end_calc_date    TYPE datum,
            end_show_date    TYPE datum,
            total_day        TYPE i,
            balance_amount   TYPE zfi_e_period_amount,
            period_amount    TYPE zfi_e_period_amount,
            remaining_amount TYPE zfi_e_period_amount,
            nc_amount        TYPE zfi_e_period_amount,
          END OF ls_period,
          lt_period LIKE TABLE OF ls_period.

    DATA: lv_counter            TYPE i,
          lv_item_day           TYPE i,
          lv_item_sum_amount    TYPE zfi_e_period_amount,
          lv_balance_amount     TYPE zfi_e_period_amount,
          lv_remaining_amount   TYPE zfi_e_period_amount,
          lv_start_date_ongoing TYPE d.

    DATA: lt_sim_insert TYPE STANDARD TABLE OF zfi_t_period_s,
          lt_item       TYPE STANDARD TABLE OF zfi_t_period_i.

    APPEND is_item TO lt_item.

*    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
*      ENTITY item
*      ALL FIELDS  WITH VALUE #( ( headeruuid      = iv_header_uuid
*                                 itemuuid         = iv_item_uuid
*                                 headerobjecttype = iv_header_object_type ) )
*      RESULT DATA(lt_item).

    LOOP AT lt_item INTO DATA(ls_item).
      CLEAR: lt_period, lv_item_sum_amount, lv_balance_amount, lv_remaining_amount,
             lv_start_date_ongoing.
      lv_counter = 1.

      SELECT * FROM zfi_t_period_s
        WHERE header_uuid = @ls_item-header_uuid AND
              header_object_type = @ls_item-header_object_type AND
              item_uuid = @ls_item-item_uuid
         INTO TABLE @DATA(lt_simulate).

      SELECT SUM( period_amount ) FROM zfi_t_period_s
        WHERE header_uuid = @ls_item-header_uuid AND
              header_object_type = @ls_item-header_object_type AND
              item_uuid = @ls_item-item_uuid AND
              simulate_comp = @abap_true
         INTO @DATA(lv_sum_created_period).

      ls_item-amount = ls_item-amount - lv_sum_created_period.

      DATA(lt_sim_delete) = lt_simulate.
      DATA(lt_sim_created) = lt_simulate.

      DELETE lt_sim_delete WHERE simulate_comp = abap_true.
      MOVE-CORRESPONDING lt_sim_delete TO lcl_buffer=>mt_buf_sim_del KEEPING TARGET LINES.

      IF ls_item-amount IS INITIAL OR
         ls_item-currency_code IS INITIAL OR
         ls_item-start_date IS INITIAL OR
         ls_item-end_date IS INITIAL OR
         ( ls_item-start_date >= ls_item-end_date ) OR
         ( ls_item-day_flag IS INITIAL AND ls_item-month_flag IS INITIAL ).
        CONTINUE.
      ENDIF.

      IF lv_sum_created_period IS INITIAL.
        DATA(lv_start_year)  = CONV i( ls_item-start_date(4) ).
        DATA(lv_start_month) = CONV i( ls_item-start_date+4(2) ).
        DATA(lv_start_day)   = CONV i( ls_item-start_date+6(2) ).

      ELSE.
        DELETE lt_sim_created WHERE simulate_comp = abap_false.
        SORT lt_sim_created BY end_show_date DESCENDING.
        lv_start_date_ongoing = lt_sim_created[ 1 ]-end_show_date + 1.

        lv_start_year  = CONV i( lv_start_date_ongoing(4) ).
        lv_start_month = CONV i( lv_start_date_ongoing+4(2) ).
        lv_start_day   = CONV i( lv_start_date_ongoing+6(2) ).
      ENDIF.

      DATA(lv_end_year)    = CONV i( ls_item-end_date(4) ).
      DATA(lv_end_month)   = CONV i( ls_item-end_date+4(2) ).
      DATA(lv_end_day)     = CONV i( ls_item-end_date+6(2) ).

      IF lv_start_date_ongoing IS NOT INITIAL.
        DATA(lv_day_difference) = ( ls_item-end_date - lv_start_date_ongoing ) + 1.
      ELSE.
        lv_day_difference = ( ls_item-end_date - ls_item-start_date ) + 1.
      ENDIF.

      DATA(lv_amount_per_day) = CONV zfi_e_period_amount_dec5( ls_item-amount / lv_day_difference ).

      WHILE lv_start_year <= lv_end_year.
        IF lv_start_year = lv_end_year.
          DATA(lv_end_month_for_year) = lv_end_month.
        ELSE.
          lv_end_month_for_year = 12.
        ENDIF.

        IF lv_counter = 1.
          DATA(lv_start_month_for_year) = lv_start_month.
        ELSE.
          lv_start_month_for_year = 1.
        ENDIF.

        WHILE lv_start_month_for_year <= lv_end_month_for_year.
          DATA(lv_next_month_first_day) = xco_cp_time=>date( iv_year  = |{ lv_start_year }|
                                                             iv_month = |{ lv_start_month_for_year }|
                                                             iv_day   = '01'
                                                     )->add( iv_month = 1
                                                       io_calculation = xco_cp_time=>date_calculation->preserving
                                                     )->as( xco_cp_time=>format->abap
                                                     )->value.

          DATA(lv_last_day_of_current_month) = xco_cp_time=>date( iv_year  = |{ lv_next_month_first_day(4) }|
                                                                  iv_month = |{ lv_next_month_first_day+4(2) }|
                                                                  iv_day   = |{ lv_next_month_first_day+6(2) }|
                                                          )->subtract( iv_day = 1
                                                            io_calculation = xco_cp_time=>date_calculation->preserving
                                                          )->as( xco_cp_time=>format->abap
                                                          )->value.

          DATA(lv_start_calc_date) = COND #( WHEN lv_counter = 1 THEN |{ lv_start_year }{ CONV zfi_e_month( lv_start_month_for_year ) }{ CONV zfi_e_day( lv_start_day ) }|
                                                                 ELSE |{ lv_start_year }{ CONV zfi_e_month( lv_start_month_for_year ) }01| ).
          DATA(lv_end_calc_date) = COND #( WHEN lv_start_year           = lv_end_year AND
                                                lv_start_month_for_year = lv_end_month  THEN |{ lv_end_year }{ CONV zfi_e_month( lv_end_month ) }{ CONV zfi_e_day( lv_end_day ) }|
                                                                                        ELSE lv_last_day_of_current_month ).
          DATA(lv_period_amount) = CONV zfi_e_period_amount( ( ( lv_end_calc_date - lv_start_calc_date ) + 1 ) * lv_amount_per_day ).

          APPEND VALUE #( period_no       = lv_counter
                          start_calc_date = lv_start_calc_date
                          start_show_date = |{ lv_start_year }{ CONV zfi_e_month( lv_start_month_for_year ) }01|
                          end_calc_date   = lv_end_calc_date
                          end_show_date   = lv_last_day_of_current_month
                          total_day       = ( lv_end_calc_date - lv_start_calc_date ) + 1
                          period_amount   = lv_period_amount ) TO lt_period.

          lv_start_month_for_year = lv_start_month_for_year + 1.
          lv_counter = lv_counter + 1.
          lv_item_sum_amount = lv_item_sum_amount + lv_period_amount.
        ENDWHILE.

        lv_start_year = lv_start_year + 1.
      ENDWHILE.

      IF ls_item-day_flag = abap_true.
        IF lt_period IS NOT INITIAL AND lv_item_sum_amount NE ls_item-amount.
          DATA(lv_difference) = CONV zfi_e_period_amount( ls_item-amount - lv_item_sum_amount ).
          lt_period[ lines( lt_period ) ]-period_amount = lt_period[ lines( lt_period ) ]-period_amount + lv_difference.
        ENDIF.
      ELSEIF ls_item-month_flag = abap_true.
        IF lt_period IS NOT INITIAL.
          DATA(lv_amount_per_month) = CONV zfi_e_period_amount( ls_item-amount / lines( lt_period ) ).
          DATA(lv_amount_total_month) = CONV zfi_e_period_amount( lv_amount_per_month * lines( lt_period ) ).
          IF lv_amount_total_month NE ls_item-amount.
            lv_difference = ls_item-amount - lv_amount_total_month.
          ENDIF.
          MODIFY lt_period FROM VALUE #( period_amount = lv_amount_per_month ) TRANSPORTING period_amount WHERE period_no IS NOT INITIAL.
          lt_period[ lines( lt_period ) ]-period_amount = lt_period[ lines( lt_period ) ]-period_amount + lv_difference.
        ENDIF.
      ENDIF.

      LOOP AT lt_period ASSIGNING FIELD-SYMBOL(<fs_period>).
        IF ls_item-currency_code <> 'TRY'.
          DATA(lv_nc_flag) = abap_false.

          IF ls_item-rate_flag = abap_true.
            DATA(lv_cur_conv_date) = ls_item-start_date.
          ELSE.
            IF lv_sum_created_period IS INITIAL.
              lv_cur_conv_date = ls_item-start_date.
            ELSE.
              lv_cur_conv_date = lt_sim_created[ 1 ]-end_show_date.
            ENDIF.
          ENDIF.

          SELECT SINGLE *
            FROM zfi_i_period_curr_conv( p_amount      = @<fs_period>-period_amount,
                                         p_source_curr = @ls_item-currency_code,
                                         p_target_curr = 'TRY',
                                         p_ratetype    = 'M',
                                         p_date        = @lv_cur_conv_date )
            INTO @DATA(ls_cur_conv).
          IF sy-subrc = 0.
            <fs_period>-nc_amount = ls_cur_conv-convertedamount.
          ENDIF.
        ELSE.
          <fs_period>-nc_amount = <fs_period>-period_amount.
          lv_nc_flag = abap_true.
        ENDIF.

        lv_balance_amount = lv_balance_amount + <fs_period>-period_amount.
        lv_remaining_amount = ls_item-amount - lv_balance_amount.
        <fs_period>-balance_amount = lv_balance_amount + lv_sum_created_period.
        <fs_period>-remaining_amount = lv_remaining_amount.

        APPEND INITIAL LINE TO lt_sim_insert ASSIGNING FIELD-SYMBOL(<fs_period_insert>).
        <fs_period_insert>-header_uuid        = ls_item-header_uuid.
        <fs_period_insert>-item_uuid          = ls_item-item_uuid.
        <fs_period_insert>-header_object_type = ls_item-header_object_type.
        <fs_period_insert>-nc_currency        = 'TRY'.
        TRY.
            <fs_period_insert>-simulate_uuid = cl_system_uuid=>create_uuid_x16_static( ).
          CATCH cx_uuid_error INTO DATA(lo_uuid_err).
        ENDTRY.

        <fs_period_insert>-balance_amount   = <fs_period>-balance_amount.
        <fs_period_insert>-currency_code    = ls_item-currency_code.
        <fs_period_insert>-end_calc_date    = <fs_period>-end_calc_date.
        <fs_period_insert>-start_calc_date  = <fs_period>-start_calc_date.
        <fs_period_insert>-start_show_date  = <fs_period>-start_show_date.
        <fs_period_insert>-end_show_date    = <fs_period>-end_show_date.
        <fs_period_insert>-period_amount    = <fs_period>-period_amount.
        <fs_period_insert>-remaining_amount = <fs_period>-remaining_amount.
        <fs_period_insert>-nc_amount        = <fs_period>-nc_amount.
        <fs_period_insert>-nc_flag          = lv_nc_flag.
      ENDLOOP.

      MOVE-CORRESPONDING lt_sim_insert TO lcl_buffer=>mt_buf_sim_cre KEEPING TARGET LINES.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS lhc_header DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR header RESULT result.

    METHODS validateheadertext FOR VALIDATE ON SAVE
      IMPORTING keys FOR header~validateheadertext.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR header RESULT result.

    METHODS get_global_features FOR GLOBAL FEATURES
      IMPORTING REQUEST requested_features FOR header RESULT result.

    METHODS validatecreateheader FOR VALIDATE ON SAVE
      IMPORTING keys FOR header~validatecreateheader.

    METHODS headerdefaultvalue FOR DETERMINE ON MODIFY
      IMPORTING keys FOR header~headerdefaultvalue.

    METHODS startobject FOR MODIFY
      IMPORTING keys FOR ACTION header~startobject RESULT result.

    METHODS stopobject FOR MODIFY
      IMPORTING keys FOR ACTION header~stopobject RESULT result.
    METHODS create FOR MODIFY
      IMPORTING entities FOR CREATE header.

    METHODS update FOR MODIFY
      IMPORTING entities FOR UPDATE header.

    METHODS delete FOR MODIFY
      IMPORTING keys FOR DELETE header.

    METHODS read FOR READ
      IMPORTING keys FOR READ header RESULT result.

    METHODS lock FOR LOCK
      IMPORTING keys FOR LOCK header.

    METHODS rba_perioditem FOR READ
      IMPORTING keys_rba FOR READ header\_perioditem FULL result_requested RESULT result LINK association_links.

    METHODS cba_perioditem FOR MODIFY
      IMPORTING entities_cba FOR CREATE header\_perioditem.
    METHODS cancelobject FOR MODIFY
      IMPORTING keys FOR ACTION header~cancelobject RESULT result.

ENDCLASS.

CLASS lhc_header IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD validateheadertext.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY header
      FIELDS ( headertext ) WITH CORRESPONDING #( keys )
      RESULT DATA(headertext).
    LOOP AT headertext INTO DATA(ls_headertext).
      IF ls_headertext-headertext IS INITIAL.
        APPEND VALUE #( %tky = ls_headertext-%tky ) TO failed-header.

        APPEND VALUE #(  %tky        = ls_headertext-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 003
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-header.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD get_instance_features.
    CHECK keys IS NOT INITIAL.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY header
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_header).

    result =
      VALUE #(
        FOR header IN lt_header
          LET is_editable  =   COND #( WHEN header-status = space
                                      THEN if_abap_behv=>fc-f-unrestricted
                                      ELSE if_abap_behv=>fc-f-read_only )
              is_updatable =   COND #( WHEN header-status = 'BAS' OR
                                            header-status = space
                                      THEN if_abap_behv=>fc-o-enabled
                                      ELSE if_abap_behv=>fc-o-disabled )
              is_startable =   COND #( WHEN header-status = 'ASK' AND
                                            header-%is_draft = if_abap_behv=>mk-off
                                      THEN if_abap_behv=>fc-o-enabled
                                      ELSE if_abap_behv=>fc-o-disabled )
              is_stoppable =   COND #( WHEN header-status = 'BAS' AND
                                            header-%is_draft = if_abap_behv=>mk-off
                                      THEN if_abap_behv=>fc-o-enabled
                                      ELSE if_abap_behv=>fc-o-disabled )
              is_cancelable =  COND #( WHEN header-%is_draft = if_abap_behv=>mk-off AND
                                             ( header-status = 'BAS' OR
                                              header-status = 'ASK' )
                                      THEN if_abap_behv=>fc-o-enabled
                                      ELSE if_abap_behv=>fc-o-disabled )
          IN
            ( %tky                     = header-%tky
              %field-companycode       = is_editable
              %field-supplier          = is_editable
              %update                  = is_updatable
              %action-edit             = is_updatable
              %action-startobject      = is_startable
              %action-stopobject       = is_stoppable
              %action-cancelobject     = is_cancelable
             ) ).
  ENDMETHOD.

  METHOD get_global_features.
    result-%delete = if_abap_behv=>fc-o-disabled.
  ENDMETHOD.

  METHOD validatecreateheader.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY header
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_header).
    LOOP AT lt_header INTO DATA(ls_header).
      SELECT SINGLE companycode FROM i_companycode
        WHERE companycode = @ls_header-companycode
        INTO @DATA(lv_companycode).
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = ls_header-%tky ) TO failed-header.

        APPEND VALUE #(  %tky        = ls_header-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 000
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-header.
      ENDIF.

      SELECT SINGLE supplier FROM i_supplier
        WHERE supplier = @ls_header-supplier
        INTO @DATA(lv_supplier).
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = ls_header-%tky ) TO failed-header.

        APPEND VALUE #(  %tky        = ls_header-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 001
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-header.
      ENDIF.

      SELECT SINGLE headerobjecttype FROM zfi_i_objtypeheader
        WHERE headerobjecttype = @ls_header-headerobjecttype
        INTO @DATA(lv_objecttype).
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = ls_header-%tky ) TO failed-header.

        APPEND VALUE #(  %tky        = ls_header-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 002
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-header.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD headerdefaultvalue.
    DATA: lt_data_header TYPE TABLE FOR UPDATE zfi_i_period_h\\header.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY header
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_header).
    LOOP AT lt_header ASSIGNING FIELD-SYMBOL(<fs_header>) WHERE createindicator = abap_false.
      SELECT SINGLE header_uuid FROM zfi_t_period_h
        WHERE header_uuid = @<fs_header>-headeruuid AND
              header_object_type = @<fs_header>-headerobjecttype
        INTO @DATA(lv_exist_uuid).
      IF sy-subrc <> 0.
        <fs_header>-createindicator = abap_true.
        IF <fs_header>-companycode IS INITIAL.
          <fs_header>-companycode = '1000'.
        ENDIF.

        APPEND VALUE #( %tky            = <fs_header>-%tky
                        createindicator = <fs_header>-createindicator
                        companycode     = <fs_header>-companycode
                      ) TO lt_data_header.
      ENDIF.
    ENDLOOP.

    IF lt_data_header IS NOT INITIAL.
      MODIFY ENTITIES OF zfi_i_period_h IN LOCAL MODE
        ENTITY header
          UPDATE FIELDS ( createindicator companycode )
          WITH CORRESPONDING #( lt_data_header ).
    ENDIF.
  ENDMETHOD.

  METHOD startobject.
    DATA: lt_data_header TYPE TABLE FOR UPDATE zfi_i_period_h\\header.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY header
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_header).
    LOOP AT lt_header INTO DATA(ls_header).
      APPEND VALUE #( %tky            = ls_header-%tky
                      status          = 'BAS'
                    ) TO lt_data_header.
    ENDLOOP.

    IF lt_data_header IS NOT INITIAL.
      MODIFY ENTITIES OF zfi_i_period_h IN LOCAL MODE
        ENTITY header
          UPDATE FIELDS ( status )
          WITH CORRESPONDING #( lt_data_header ).

      APPEND VALUE #(  %tky        = ls_header-%tky
                       %msg        = new_message(
                                      id       = 'ZFI_PERIOD_MSG'
                                      number   = 027
                                      severity = if_abap_behv_message=>severity-success ) ) TO reported-header.

      APPEND INITIAL LINE TO result ASSIGNING FIELD-SYMBOL(<fs_result>).
      <fs_result>-%tky = ls_header-%tky.
      <fs_result>-%param-headerobjecttype = ls_header-headerobjecttype.
      <fs_result>-%param-headeruuid = ls_header-headeruuid.
    ENDIF.
  ENDMETHOD.

  METHOD stopobject.
    DATA: lt_data_header TYPE TABLE FOR UPDATE zfi_i_period_h\\header.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY header
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_header).
    LOOP AT lt_header INTO DATA(ls_header).
      APPEND VALUE #( %tky            = ls_header-%tky
                      status          = 'ASK'
                    ) TO lt_data_header.
    ENDLOOP.

    IF lt_data_header IS NOT INITIAL.
      MODIFY ENTITIES OF zfi_i_period_h IN LOCAL MODE
        ENTITY header
          UPDATE FIELDS ( status )
          WITH CORRESPONDING #( lt_data_header ).

      APPEND VALUE #(  %tky        = ls_header-%tky
                       %msg        = new_message(
                                      id       = 'ZFI_PERIOD_MSG'
                                      number   = 028
                                      severity = if_abap_behv_message=>severity-success ) ) TO reported-header.

      APPEND INITIAL LINE TO result ASSIGNING FIELD-SYMBOL(<fs_result>).
      <fs_result>-%tky = ls_header-%tky.
      <fs_result>-%param-headerobjecttype = ls_header-headerobjecttype.
      <fs_result>-%param-headeruuid = ls_header-headeruuid.
    ENDIF.
  ENDMETHOD.


  METHOD create.
    DATA: period_header_log TYPE STANDARD TABLE OF zfi_t_period_h.

    period_header_log = CORRESPONDING #( entities MAPPING FROM ENTITY ).

    LOOP AT period_header_log ASSIGNING FIELD-SYMBOL(<fs_header_log>).
      DATA(lv_object_type) = <fs_header_log>-header_object_type.

      SELECT SINGLE number_range_no FROM zfi_t_obj_type_h
        WHERE header_object_type = @lv_object_type
        INTO @DATA(lv_number_range_no).

      TRY.
          cl_numberrange_runtime=>number_get(
            EXPORTING
              nr_range_nr       = lv_number_range_no
              object            = 'ZFI_OBJ_NO'
              quantity          = 1
            IMPORTING
              number            = DATA(lv_number)
              returncode        = DATA(lv_return_code)
              returned_quantity = DATA(lv_return_quan)
          ).
        CATCH cx_number_ranges INTO DATA(lx_number_ranges).
      ENDTRY.

      DATA(lv_string_num) = CONV string( lv_number ).
      lv_string_num = |{ lv_string_num ALPHA = OUT }|.

      <fs_header_log>-status = 'BAS'.
      <fs_header_log>-object_number = lv_string_num.
    ENDLOOP.

    lcl_buffer=>mt_header_log_create = period_header_log.
  ENDMETHOD.

  METHOD update.
    DATA: period_header_log_upd TYPE STANDARD TABLE OF zfi_t_period_h,
          period_header_cntrl   TYPE STANDARD TABLE OF zfi_s_cntrl_per_h,
          period_header_log     TYPE STANDARD TABLE OF zfi_t_period_h.

    period_header_log_upd = CORRESPONDING #( entities MAPPING FROM ENTITY ).
    period_header_cntrl = CORRESPONDING #( entities MAPPING FROM ENTITY USING CONTROL ).

    SELECT * FROM zfi_t_period_h
    FOR ALL ENTRIES IN @entities
    WHERE header_uuid = @entities-headeruuid AND
          header_object_type = @entities-headerobjecttype
      INTO TABLE @DATA(lt_header_old).

    period_header_log = VALUE #(  FOR x = 1 WHILE x <= lines( lt_header_old )
                                  LET
                                    controlflag = VALUE #( period_header_cntrl[ x ] OPTIONAL )
                                    header_upd  = VALUE #( period_header_log_upd[ x ] OPTIONAL )
                                    header_old  = VALUE #( lt_header_old[ header_uuid        = header_upd-header_uuid
                                                                          header_object_type = header_upd-header_object_type ] OPTIONAL )
                                  IN
                                  (
                                      header_uuid           = header_old-header_uuid
                                      header_object_type    = header_old-header_object_type
                                      object_number         = COND #( WHEN controlflag-object_number IS NOT INITIAL THEN header_upd-object_number ELSE header_old-object_number )
                                      company_code          = COND #( WHEN controlflag-company_code IS NOT INITIAL THEN header_upd-company_code ELSE header_old-company_code )
                                      supplier              = COND #( WHEN controlflag-supplier IS NOT INITIAL THEN header_upd-supplier ELSE header_old-supplier )
                                      status                = COND #( WHEN controlflag-status IS NOT INITIAL THEN header_upd-status ELSE header_old-status )
                                      header_text           = COND #( WHEN controlflag-header_text IS NOT INITIAL THEN header_upd-header_text ELSE header_old-header_text )
                                      local_last_changed_at = COND #( WHEN controlflag-local_last_changed_at IS NOT INITIAL THEN header_upd-local_last_changed_at ELSE header_old-local_last_changed_at )
                                  )
                               ).

    lcl_buffer=>mt_header_log_update = period_header_log.
  ENDMETHOD.

  METHOD delete.
  ENDMETHOD.

  METHOD read.
    LOOP AT keys INTO DATA(ls_key).
      SELECT SINGLE * FROM zfi_i_period_h
        WHERE headeruuid EQ @ls_key-headeruuid
          AND headerobjecttype EQ @ls_key-headerobjecttype
        INTO @DATA(ls_header).
      IF sy-subrc EQ 0.
        APPEND CORRESPONDING #( ls_header ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD lock.
  ENDMETHOD.

  METHOD rba_perioditem.
  ENDMETHOD.

  METHOD cba_perioditem.
    DATA: period_item_log TYPE STANDARD TABLE OF zfi_t_period_i,
          period_item_cds TYPE STANDARD TABLE OF zfi_i_period_i.

    LOOP AT entities_cba INTO DATA(ls_cba).
      MOVE-CORRESPONDING ls_cba-%target TO period_item_cds KEEPING TARGET LINES.
    ENDLOOP.

    period_item_log = CORRESPONDING #( period_item_cds MAPPING FROM ENTITY ).

    LOOP AT period_item_log ASSIGNING FIELD-SYMBOL(<fs_item_log>).
      <fs_item_log>-item_status = 'YRT'.

      IF <fs_item_log>-end_date(4) EQ <fs_item_log>-start_date(4).
        <fs_item_log>-bill_extra_flag = abap_true.
      ENDIF.

      lcl_buffer=>simulate_all( EXPORTING is_item = <fs_item_log> ).
    ENDLOOP.

    lcl_buffer=>mt_item_log_create = period_item_log.
  ENDMETHOD.

  METHOD cancelobject.
    DATA: lt_data_header TYPE TABLE FOR UPDATE zfi_i_period_h\\header.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY header
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_header).
    LOOP AT lt_header INTO DATA(ls_header).
      APPEND VALUE #( %tky            = ls_header-%tky
                      status          = 'IPT'
                    ) TO lt_data_header.
    ENDLOOP.

    IF lt_data_header IS NOT INITIAL.
      MODIFY ENTITIES OF zfi_i_period_h IN LOCAL MODE
        ENTITY header
          UPDATE FIELDS ( status )
          WITH CORRESPONDING #( lt_data_header ).

      APPEND VALUE #(  %tky        = ls_header-%tky
                       %msg        = new_message(
                                      id       = 'ZFI_PERIOD_MSG'
                                      number   = 032
                                      severity = if_abap_behv_message=>severity-success ) ) TO reported-header.

      APPEND INITIAL LINE TO result ASSIGNING FIELD-SYMBOL(<fs_result>).
      <fs_result>-%tky = ls_header-%tky.
      <fs_result>-%param-headerobjecttype = ls_header-headerobjecttype.
      <fs_result>-%param-headeruuid = ls_header-headeruuid.
    ENDIF.
  ENDMETHOD.

ENDCLASS.

CLASS lhc_item DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR item RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR item RESULT result.

    METHODS get_global_features FOR GLOBAL FEATURES
      IMPORTING REQUEST requested_features FOR item RESULT result.

    METHODS validateamount FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validateamount.

    METHODS validatecostacc FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validatecostacc.

    METHODS validatecostcenter FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validatecostcenter.

    METHODS validatecurrency FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validatecurrency.

    METHODS validateenddate FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validateenddate.

    METHODS validateitemtype FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validateitemtype.

    METHODS validatemainacc FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validatemainacc.

    METHODS validatentdeacc FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validatentdeacc.

    METHODS validatestartdate FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validatestartdate.

    METHODS validatewbselement FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validatewbselement.

    METHODS determinentdeacc FOR DETERMINE ON MODIFY
      IMPORTING keys FOR item~determinentdeacc.

    METHODS determinecostacc FOR DETERMINE ON MODIFY
      IMPORTING keys FOR item~determinecostacc.

    METHODS determinedaycalc FOR DETERMINE ON MODIFY
      IMPORTING keys FOR item~determinedaycalc.

    METHODS determinemonthcalc FOR DETERMINE ON MODIFY
      IMPORTING keys FOR item~determinemonthcalc.

    METHODS validatedocumenttype FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validatedocumenttype.

    METHODS determinecurrency FOR DETERMINE ON MODIFY
      IMPORTING keys FOR item~determinecurrency.

    METHODS determinerateflag FOR DETERMINE ON MODIFY
      IMPORTING keys FOR item~determinerateflag.

    METHODS createbill FOR MODIFY
      IMPORTING keys FOR ACTION item~createbill RESULT result.

    METHODS getdefaultsforbill FOR READ
      IMPORTING keys FOR FUNCTION item~getdefaultsforbill RESULT result.

    METHODS determinecreatebill FOR DETERMINE ON SAVE
      IMPORTING keys FOR item~determinecreatebill.
    METHODS update FOR MODIFY
      IMPORTING entities FOR UPDATE item.

    METHODS delete FOR MODIFY
      IMPORTING keys FOR DELETE item.

    METHODS read FOR READ
      IMPORTING keys FOR READ item RESULT result.

    METHODS rba_periodheader FOR READ
      IMPORTING keys_rba FOR READ item\_periodheader FULL result_requested RESULT result LINK association_links.

    METHODS rba_periodsimulation FOR READ
      IMPORTING keys_rba FOR READ item\_periodsimulation FULL result_requested RESULT result LINK association_links.

    METHODS cba_periodsimulation FOR MODIFY
      IMPORTING entities_cba FOR CREATE item\_periodsimulation.

    METHODS itemdefaultvalue FOR DETERMINE ON MODIFY
      IMPORTING keys FOR item~itemdefaultvalue.
    METHODS reversebill FOR MODIFY
      IMPORTING keys FOR ACTION item~reversebill RESULT result.
    METHODS validatedaycalc FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validatedaycalc.

    METHODS validatemonthcalc FOR VALIDATE ON SAVE
      IMPORTING keys FOR item~validatemonthcalc.

ENDCLASS.

CLASS lhc_item IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.


  METHOD get_instance_features.
    CHECK keys IS NOT INITIAL.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY header
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_header).

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_item).

    result =
      VALUE #(
        FOR item IN lt_item
          LET is_editable_calc = COND #( WHEN item-itemstatus = 'YRT' OR
                                              item-itemstatus = space THEN if_abap_behv=>fc-f-unrestricted
                                           ELSE if_abap_behv=>fc-f-read_only )
              is_editable_comp = COND #( WHEN item-itemstatus = 'TAM' THEN if_abap_behv=>fc-f-read_only
                                           ELSE if_abap_behv=>fc-f-unrestricted )
              is_ntde_upd      = COND #( WHEN item-vehicleflag = abap_true AND
                                              item-itemstatus <> 'TAM' THEN if_abap_behv=>fc-f-unrestricted
                                                                       ELSE if_abap_behv=>fc-f-read_only )
              is_updatable     = COND #( WHEN lt_header[ 1 ]-status = 'ASK' OR
                                              lt_header[ 1 ]-status = 'IPT'
                                        THEN if_abap_behv=>fc-o-disabled
                                        ELSE if_abap_behv=>fc-o-enabled )
              is_billable     = COND #( WHEN item-%is_draft = if_abap_behv=>mk-off AND
                                             item-itemstatus = 'YRT' AND
                                             lt_header[ 1 ]-status NE 'ASK' AND
                                             lt_header[ 1 ]-status NE 'IPT' AND
                                             item-billnumber IS INITIAL
                                        THEN if_abap_behv=>fc-o-enabled
                                        ELSE if_abap_behv=>fc-o-disabled )
              is_revbill     = COND #( WHEN  item-%is_draft = if_abap_behv=>mk-off AND
                                             item-itemstatus = 'YRT' AND
                                             lt_header[ 1 ]-status NE 'ASK' AND
                                             lt_header[ 1 ]-status NE 'IPT' AND
                                            item-billnumber IS NOT INITIAL
                                        THEN if_abap_behv=>fc-o-enabled
                                        ELSE if_abap_behv=>fc-o-disabled )
          IN
            ( %tky                   = item-%tky
              %field-costaccount     = is_editable_comp
              %field-costcenter      = is_editable_comp
              %field-enddate         = is_editable_comp
              %field-vehicleflag     = is_editable_comp
              %field-mainaccount     = is_editable_comp
              %field-documenttype    = is_editable_comp
              %field-rateflag        = is_editable_calc
              %field-wbselement      = is_editable_comp
              %field-currencycode    = is_editable_calc
              %field-amount          = is_editable_calc
              %field-monthflag       = is_editable_comp
              %field-dayflag         = is_editable_comp
              %field-startdate       = is_editable_calc
              %field-itemobjecttype  = is_editable_calc
              %field-ntdeaccount     = is_ntde_upd
              %update                = is_updatable
              %action-createbill     = is_billable
              %action-reversebill    = is_revbill
             ) ).
  ENDMETHOD.

  METHOD get_global_features.
    result-%delete = if_abap_behv=>fc-o-disabled.
  ENDMETHOD.

  METHOD validateamount.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      FIELDS ( amount ) WITH CORRESPONDING #( keys )
      RESULT DATA(amount).
    LOOP AT amount INTO DATA(ls_amount).
      DATA(lv_tabix) = sy-tabix.
      IF ls_amount-amount IS INITIAL.
        APPEND VALUE #( %tky = ls_amount-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_amount-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 004
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validatecostacc.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      FIELDS ( costaccount ) WITH CORRESPONDING #( keys )
      RESULT DATA(costaccount).
    LOOP AT costaccount INTO DATA(ls_costaccount).
      DATA(lv_tabix) = sy-tabix.

      SELECT SINGLE glaccount FROM i_glaccount
        WHERE glaccount = @ls_costaccount-costaccount
        INTO @DATA(lv_glaccount).
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = ls_costaccount-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_costaccount-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 006
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validatecostcenter.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      FIELDS ( costcenter ) WITH CORRESPONDING #( keys )
      RESULT DATA(costcenter).
    LOOP AT costcenter INTO DATA(ls_costcenter).
      DATA(lv_tabix) = sy-tabix.

      SELECT SINGLE costcenter FROM i_costcenter
        WHERE controllingarea = 'A000' AND
              validityenddate = '99991231' AND
              costcenter      = @ls_costcenter-costcenter
        INTO @DATA(lv_costcenter).
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = ls_costcenter-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_costcenter-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 005
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validatecurrency.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      FIELDS ( currencycode rateflag startdate amount ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_currency).
    LOOP AT lt_currency INTO DATA(ls_currency).
      DATA(lv_tabix) = sy-tabix.

      SELECT SINGLE currency FROM i_currency
        WHERE currency = @ls_currency-currencycode
        INTO @DATA(lv_currency).
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = ls_currency-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_currency-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 007
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ELSE.
        IF ls_currency-currencycode = 'TRY' AND ls_currency-rateflag = abap_true.
          APPEND VALUE #( %tky = ls_currency-%tky ) TO failed-item.

          APPEND VALUE #(  %tky        = ls_currency-%tky
                           %msg        = new_message(
                                          id       = 'ZFI_PERIOD_MSG'
                                          number   = 025
                                          v1       = lv_tabix
                                          severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
        ENDIF.

        IF ls_currency-currencycode <> 'TRY'.
          DATA(lv_conv_error) = abap_false.
          DATA(lv_dummy_currency) = CONV zfi_e_period_amount( 10 ).
          TRY.
              SELECT SINGLE *
                FROM zfi_i_period_curr_conv( p_amount      = @lv_dummy_currency,
                                             p_source_curr = @ls_currency-currencycode,
                                             p_target_curr = 'TRY',
                                             p_ratetype    = 'M',
                                             p_date        = @ls_currency-startdate )
                INTO @DATA(ls_cur_conv).
              IF ls_cur_conv-convertedamount IS INITIAL.
                lv_conv_error = abap_true.
              ENDIF.
            CATCH cx_sy_open_sql_db INTO DATA(lx_open_sql).
              lv_conv_error = abap_true.
          ENDTRY.

          IF lv_conv_error = abap_true.
            APPEND VALUE #( %tky = ls_currency-%tky ) TO failed-item.

            APPEND VALUE #(  %tky        = ls_currency-%tky
                             %msg        = new_message(
                                            id       = 'ZFI_PERIOD_MSG'
                                            number   = 026
                                            v1       = lv_tabix
                                            severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validateenddate.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(dates).
    LOOP AT dates INTO DATA(ls_date).
      DATA(lv_tabix) = sy-tabix.

      IF ls_date-enddate IS INITIAL.
        APPEND VALUE #( %tky = ls_date-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_date-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 013
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ELSE.
        IF ls_date-startdate IS NOT INITIAL AND ls_date-enddate <= ls_date-startdate.
          APPEND VALUE #( %tky = ls_date-%tky ) TO failed-item.

          APPEND VALUE #(  %tky        = ls_date-%tky
                           %msg        = new_message(
                                          id       = 'ZFI_PERIOD_MSG'
                                          number   = 014
                                          v1       = lv_tabix
                                          severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
        ELSE.
          SELECT * FROM zfi_t_period_s
            WHERE header_uuid = @ls_date-headeruuid AND
                  item_uuid   = @ls_date-itemuuid AND
                  header_object_type = @ls_date-headerobjecttype AND
                  simulate_comp = @abap_true
            INTO TABLE @DATA(lt_period_s).
          IF sy-subrc = 0.
            SORT lt_period_s BY end_show_date DESCENDING.
            DATA(lv_latest_control_day) = lt_period_s[ 1 ]-end_show_date.
            IF ls_date-enddate <= lv_latest_control_day.
              APPEND VALUE #( %tky = ls_date-%tky ) TO failed-item.

              APPEND VALUE #(  %tky        = ls_date-%tky
                               %msg        = new_message(
                                              id       = 'ZFI_PERIOD_MSG'
                                              number   = 021
                                              v1       = lv_tabix
                                              severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validateitemtype.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      FIELDS ( headerobjecttype itemobjecttype ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_objecttype).
    LOOP AT lt_objecttype INTO DATA(ls_objecttype).
      DATA(lv_tabix) = sy-tabix.

      SELECT SINGLE itemobjecttype FROM zfi_i_obj_type_i
        WHERE headerobjecttype = @ls_objecttype-headerobjecttype
          AND itemobjecttype   = @ls_objecttype-itemobjecttype
        INTO @DATA(lv_itemobjecttype).
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = ls_objecttype-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_objecttype-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 012
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validatemainacc.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      FIELDS ( mainaccount ) WITH CORRESPONDING #( keys )
      RESULT DATA(mainaccount).
    LOOP AT mainaccount INTO DATA(ls_mainaccount).
      DATA(lv_tabix) = sy-tabix.

      SELECT SINGLE glaccount FROM i_glaccount
        WHERE glaccount = @ls_mainaccount-mainaccount
        INTO @DATA(lv_mainaccount).
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = ls_mainaccount-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_mainaccount-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 008
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validatentdeacc.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      FIELDS ( ntdeaccount vehicleflag ) WITH CORRESPONDING #( keys )
      RESULT DATA(vehicle).
    LOOP AT vehicle INTO DATA(ls_vehicle).
      DATA(lv_tabix) = sy-tabix.

      IF ls_vehicle-vehicleflag IS INITIAL AND ls_vehicle-ntdeaccount IS NOT INITIAL.
        APPEND VALUE #( %tky = ls_vehicle-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_vehicle-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 009
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ELSEIF ls_vehicle-vehicleflag IS NOT INITIAL AND ls_vehicle-ntdeaccount IS INITIAL.
        APPEND VALUE #( %tky = ls_vehicle-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_vehicle-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 010
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ELSEIF ls_vehicle-vehicleflag IS NOT INITIAL AND ls_vehicle-ntdeaccount IS NOT INITIAL.
        SELECT SINGLE glaccount FROM i_glaccount
          WHERE glaccount = @ls_vehicle-ntdeaccount
          INTO @DATA(lv_ntdeaccount).
        IF sy-subrc <> 0.
          APPEND VALUE #( %tky = ls_vehicle-%tky ) TO failed-item.

          APPEND VALUE #(  %tky        = ls_vehicle-%tky
                           %msg        = new_message(
                                          id       = 'ZFI_PERIOD_MSG'
                                          number   = 011
                                          v1       = lv_tabix
                                          severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validatestartdate.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      FIELDS ( startdate enddate ) WITH CORRESPONDING #( keys )
      RESULT DATA(dates).
    LOOP AT dates INTO DATA(ls_date).
      DATA(lv_tabix) = sy-tabix.

      IF ls_date-startdate IS INITIAL.
        APPEND VALUE #( %tky = ls_date-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_date-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 015
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ELSE.
        IF ls_date-enddate IS NOT INITIAL AND ls_date-startdate >= ls_date-enddate.
          APPEND VALUE #( %tky = ls_date-%tky ) TO failed-item.

          APPEND VALUE #(  %tky        = ls_date-%tky
                           %msg        = new_message(
                                          id       = 'ZFI_PERIOD_MSG'
                                          number   = 016
                                          v1       = lv_tabix
                                          severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validatewbselement.

  ENDMETHOD.

  METHOD determinentdeacc.
    DATA: lt_data_upt TYPE TABLE FOR UPDATE zfi_i_period_h\\item.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).
    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<fs_data>).
      IF <fs_data>-vehicleflag = abap_false.
        APPEND VALUE #( %tky        = <fs_data>-%tky
                        ntdeaccount = space
                      ) TO lt_data_upt.
      ENDIF.
    ENDLOOP.

    MODIFY ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
        UPDATE FIELDS ( ntdeaccount )
        WITH CORRESPONDING #( lt_data_upt ).
  ENDMETHOD.

  METHOD determinecostacc.
    DATA: lt_data_upt TYPE TABLE FOR UPDATE zfi_i_period_h\\item.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).
    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<fs_data>).
      SELECT SINGLE * FROM zfi_i_obj_type_i
        WHERE headerobjecttype = @<fs_data>-headerobjecttype AND
              itemobjecttype   = @<fs_data>-itemobjecttype
        INTO @DATA(ls_obj_type).
      IF sy-subrc = 0.
        APPEND VALUE #( %tky         = <fs_data>-%tky
                        costaccount  = ls_obj_type-costaccount
                        mainaccount  = ls_obj_type-mainaccount
                        documenttype = ls_obj_type-documenttype
                      ) TO lt_data_upt.
      ENDIF.
    ENDLOOP.

    MODIFY ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
        UPDATE FIELDS ( costaccount mainaccount documenttype )
        WITH CORRESPONDING #( lt_data_upt ).
  ENDMETHOD.

  METHOD determinemonthcalc.
    DATA: lt_data_upt TYPE TABLE FOR UPDATE zfi_i_period_h\\item.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      FIELDS ( dayflag ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).
    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<fs_data>).
      IF <fs_data>-dayflag = abap_true.
        DATA(lv_month_flag) = abap_false.
        APPEND VALUE #( %tky        = <fs_data>-%tky
                        monthflag   = lv_month_flag
                      ) TO lt_data_upt.
      ENDIF.
    ENDLOOP.

    IF lt_data_upt IS NOT INITIAL.
      MODIFY ENTITIES OF zfi_i_period_h IN LOCAL MODE
        ENTITY item
          UPDATE FIELDS ( monthflag )
          WITH CORRESPONDING #( lt_data_upt ).
    ENDIF.
  ENDMETHOD.

  METHOD determinedaycalc.
    DATA: lt_data_upt TYPE TABLE FOR UPDATE zfi_i_period_h\\item.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      FIELDS ( monthflag ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).
    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<fs_data>).
      IF <fs_data>-monthflag = abap_true.
        DATA(lv_day_flag) = abap_false.
        APPEND VALUE #( %tky        = <fs_data>-%tky
                        dayflag     = lv_day_flag
                      ) TO lt_data_upt.
      ENDIF.
    ENDLOOP.

    IF lt_data_upt IS NOT INITIAL.
      MODIFY ENTITIES OF zfi_i_period_h IN LOCAL MODE
        ENTITY item
          UPDATE FIELDS ( dayflag )
          WITH CORRESPONDING #( lt_data_upt ).
    ENDIF.
  ENDMETHOD.

*  METHOD simulateitem.
*    DATA: BEGIN OF ls_period,
*            period_no        TYPE i,
*            start_calc_date  TYPE datum,
*            start_show_date  TYPE datum,
*            end_calc_date    TYPE datum,
*            end_show_date    TYPE datum,
*            total_day        TYPE i,
*            balance_amount   TYPE zfi_e_period_amount,
*            period_amount    TYPE zfi_e_period_amount,
*            remaining_amount TYPE zfi_e_period_amount,
*          END OF ls_period,
*          lt_period LIKE TABLE OF ls_period.
*
*    DATA: lv_counter          TYPE i,
*          lv_item_day         TYPE i,
*          lv_item_sum_amount  TYPE zfi_e_period_amount,
*          lv_balance_amount   TYPE zfi_e_period_amount,
*          lv_remaining_amount TYPE zfi_e_period_amount.
*
*    DATA: lt_sim_insert TYPE STANDARD TABLE OF zfi_t_period_s.
*
*    CHECK keys IS NOT INITIAL.
*
*    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
*      ENTITY item
*      ALL FIELDS WITH CORRESPONDING #( keys )
*      RESULT DATA(lt_item).
*
*    LOOP AT lt_item INTO DATA(ls_item).
*      CLEAR: lt_period, lv_item_sum_amount, lv_balance_amount, lv_remaining_amount.
*      lv_counter = 1.
*
*      SELECT * FROM zfi_t_period_s
*        WHERE header_uuid = @ls_item-headeruuid AND
*              header_object_type = @ls_item-headerobjecttype AND
*              item_uuid = @ls_item-itemuuid
*         INTO TABLE @DATA(lt_simulate).
*
*      DATA(lt_sim_delete) = lt_simulate.
*      DELETE lt_sim_delete WHERE simulate_comp = abap_true.
*      MOVE-CORRESPONDING lt_sim_delete TO lcl_buffer=>mt_buf_sim_del KEEPING TARGET LINES.
*
*      IF ls_item-amount IS INITIAL OR
*         ls_item-currencycode IS INITIAL OR
*         ls_item-startdate IS INITIAL OR
*         ls_item-enddate IS INITIAL OR
*         ( ls_item-startdate >= ls_item-enddate ) OR
*         ( ls_item-dayflag IS INITIAL AND ls_item-monthflag IS INITIAL ).
*        CONTINUE.
*      ENDIF.
*
*      DATA(lv_start_year)  = CONV i( ls_item-startdate(4) ).
*      DATA(lv_start_month) = CONV i( ls_item-startdate+4(2) ).
*      DATA(lv_start_day)   = CONV i( ls_item-startdate+6(2) ).
*      DATA(lv_end_year)    = CONV i( ls_item-enddate(4) ).
*      DATA(lv_end_month)   = CONV i( ls_item-enddate+4(2) ).
*      DATA(lv_end_day)     = CONV i( ls_item-enddate+6(2) ).
*
*
*      DATA(lv_day_difference) = ( ls_item-enddate - ls_item-startdate ) + 1.
*      DATA(lv_amount_per_day) = CONV zfi_e_period_amount_dec5( ls_item-amount / lv_day_difference ).
*
*      WHILE lv_start_year <= lv_end_year.
*        IF lv_start_year = lv_end_year.
*          DATA(lv_end_month_for_year) = lv_end_month.
*        ELSE.
*          lv_end_month_for_year = 12.
*        ENDIF.
*
*        IF lv_counter = 1.
*          DATA(lv_start_month_for_year) = lv_start_month.
*        ELSE.
*          lv_start_month_for_year = 1.
*        ENDIF.
*
*        WHILE lv_start_month_for_year <= lv_end_month_for_year.
*          DATA(lv_next_month_first_day) = xco_cp_time=>date( iv_year  = |{ lv_start_year }|
*                                                             iv_month = |{ lv_start_month_for_year }|
*                                                             iv_day   = '01'
*                                                     )->add( iv_month = 1
*                                                       io_calculation = xco_cp_time=>date_calculation->preserving
*                                                     )->as( xco_cp_time=>format->abap
*                                                     )->value.
*
*          DATA(lv_last_day_of_current_month) = xco_cp_time=>date( iv_year  = |{ lv_next_month_first_day(4) }|
*                                                                  iv_month = |{ lv_next_month_first_day+4(2) }|
*                                                                  iv_day   = |{ lv_next_month_first_day+6(2) }|
*                                                          )->subtract( iv_day = 1
*                                                            io_calculation = xco_cp_time=>date_calculation->preserving
*                                                          )->as( xco_cp_time=>format->abap
*                                                          )->value.
*
*          DATA(lv_start_calc_date) = COND #( WHEN lv_counter = 1 THEN |{ lv_start_year }{ CONV zfi_e_month( lv_start_month_for_year ) }{ CONV zfi_e_day( lv_start_day ) }|
*                                                                 ELSE |{ lv_start_year }{ CONV zfi_e_month( lv_start_month_for_year ) }01| ).
*          DATA(lv_end_calc_date) = COND #( WHEN lv_start_year           = lv_end_year AND
*                                                lv_start_month_for_year = lv_end_month  THEN |{ lv_end_year }{ CONV zfi_e_month( lv_end_month ) }{ CONV zfi_e_day( lv_end_day ) }|
*                                                                                        ELSE lv_last_day_of_current_month ).
*          DATA(lv_period_amount) = CONV zfi_e_period_amount( ( ( lv_end_calc_date - lv_start_calc_date ) + 1 ) * lv_amount_per_day ).
*
*          APPEND VALUE #( period_no       = lv_counter
*                          start_calc_date = lv_start_calc_date
*                          start_show_date = |{ lv_start_year }{ CONV zfi_e_month( lv_start_month_for_year ) }01|
*                          end_calc_date   = lv_end_calc_date
*                          end_show_date   = lv_last_day_of_current_month
*                          total_day       = ( lv_end_calc_date - lv_start_calc_date ) + 1
*                          period_amount   = lv_period_amount ) TO lt_period.
*
*          lv_start_month_for_year = lv_start_month_for_year + 1.
*          lv_counter = lv_counter + 1.
*          lv_item_sum_amount = lv_item_sum_amount + lv_period_amount.
*        ENDWHILE.
*
*        lv_start_year = lv_start_year + 1.
*      ENDWHILE.
*
*      IF lt_period IS NOT INITIAL AND lv_item_sum_amount NE ls_item-amount.
*        DATA(lv_difference) = CONV zfi_e_period_amount( ls_item-amount - lv_item_sum_amount ).
*        lt_period[ lines( lt_period ) ]-period_amount = lt_period[ lines( lt_period ) ]-period_amount + lv_difference.
*      ENDIF.
*
*      LOOP AT lt_period ASSIGNING FIELD-SYMBOL(<fs_period>).
*        lv_balance_amount = lv_balance_amount + <fs_period>-period_amount.
*        lv_remaining_amount = ls_item-amount - lv_balance_amount.
*        <fs_period>-balance_amount = lv_balance_amount.
*        <fs_period>-remaining_amount = lv_remaining_amount.
*
*        APPEND INITIAL LINE TO lt_sim_insert ASSIGNING FIELD-SYMBOL(<fs_period_insert>).
*        <fs_period_insert>-header_uuid        = ls_item-headeruuid.
*        <fs_period_insert>-item_uuid          = ls_item-itemuuid.
*        <fs_period_insert>-header_object_type = ls_item-headerobjecttype.
*        TRY.
*            <fs_period_insert>-simulate_uuid = cl_system_uuid=>create_uuid_x16_static( ).
*          CATCH cx_uuid_error INTO DATA(lo_uuid_err).
*        ENDTRY.
*
*        <fs_period_insert>-balance_amount   = <fs_period>-balance_amount.
*        <fs_period_insert>-currency_code    = ls_item-currencycode.
*        <fs_period_insert>-end_calc_date    = <fs_period>-end_calc_date.
*        <fs_period_insert>-start_calc_date  = <fs_period>-start_calc_date.
*        <fs_period_insert>-start_show_date  = <fs_period>-start_show_date.
*        <fs_period_insert>-end_show_date    = <fs_period>-end_show_date.
*        <fs_period_insert>-period_amount    = <fs_period>-period_amount.
*        <fs_period_insert>-remaining_amount = <fs_period>-remaining_amount.
*      ENDLOOP.
*
*      MOVE-CORRESPONDING lt_sim_insert TO lcl_buffer=>mt_buf_sim_cre KEEPING TARGET LINES.
*    ENDLOOP.
*
*    APPEND INITIAL LINE TO result ASSIGNING FIELD-SYMBOL(<fs_result>).
*    <fs_result>-%key = CORRESPONDING #( keys[ 1 ] ).
*    <fs_result>-%param = CORRESPONDING #( keys[ 1 ] ).
*
*    APPEND INITIAL LINE TO mapped-item ASSIGNING FIELD-SYMBOL(<fs_mapped>).
*    <fs_mapped>-%key = CORRESPONDING #( keys[ 1 ] ).
*
*    APPEND VALUE #(  %msg   = new_message(
*                                    id       = 'ZFI_PERIOD_MSG'
*                                    number   = 017
*                                    severity = if_abap_behv_message=>severity-success ) )
*      TO reported-item.
*  ENDMETHOD.

  METHOD validatedocumenttype.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      FIELDS ( documenttype ) WITH CORRESPONDING #( keys )
      RESULT DATA(documenttype).
    LOOP AT documenttype INTO DATA(ls_documenttype).
      DATA(lv_tabix) = sy-tabix.

      SELECT SINGLE accountingdocumenttype FROM i_accountingdocumenttype
        WHERE accountingdocumenttype = @ls_documenttype-documenttype
        INTO @DATA(lv_documenttype).
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = ls_documenttype-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_documenttype-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 018
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD determinecurrency.
    DATA: lt_data_upt TYPE TABLE FOR UPDATE zfi_i_period_h\\item.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).
    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<fs_data>).
      IF <fs_data>-rateflag = abap_true AND <fs_data>-currencycode = 'TRY'.
        APPEND VALUE #( %tky         = <fs_data>-%tky
                        currencycode = space
                      ) TO lt_data_upt.
      ENDIF.
    ENDLOOP.

    IF lt_data_upt IS NOT INITIAL.
      MODIFY ENTITIES OF zfi_i_period_h IN LOCAL MODE
        ENTITY item
          UPDATE FIELDS ( currencycode )
          WITH CORRESPONDING #( lt_data_upt ).
    ENDIF.
  ENDMETHOD.

  METHOD determinerateflag.
    DATA: lt_data_upt TYPE TABLE FOR UPDATE zfi_i_period_h\\item.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).
    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<fs_data>).
      IF <fs_data>-currencycode = 'TRY'.
        DATA(lv_rate_flag) = abap_false.
        APPEND VALUE #( %tky     = <fs_data>-%tky
                        rateflag = lv_rate_flag
                      ) TO lt_data_upt.
      ENDIF.
    ENDLOOP.

    IF lt_data_upt IS NOT INITIAL.
      MODIFY ENTITIES OF zfi_i_period_h IN LOCAL MODE
        ENTITY item
          UPDATE FIELDS ( rateflag )
          WITH CORRESPONDING #( lt_data_upt ).
    ENDIF.
  ENDMETHOD.

  METHOD createbill.
    DATA: lt_jentry  TYPE TABLE FOR ACTION IMPORT i_journalentrytp~post,
          ls_jentry  LIKE LINE OF lt_jentry,
          ls_glitem  LIKE LINE OF ls_jentry-%param-_glitems,
          ls_apitem  LIKE LINE OF ls_jentry-%param-_apitems,
          ls_amount  LIKE LINE OF ls_glitem-_currencyamount,
          lv_sum_280 TYPE zfi_i_period_s-periodamount,
          lv_sum_180 TYPE zfi_i_period_s-periodamount.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY header
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_header).

    CHECK lt_data IS NOT INITIAL.

    DATA(ls_header) = lt_header[ 1 ].
    DATA(ls_item) = lt_data[ 1 ].
    DATA(ls_param) = keys[ 1 ]-%param.
    DATA(ls_key) = keys[ 1 ].

    SELECT * FROM zfi_t_period_s
      WHERE header_uuid = @ls_item-headeruuid AND
            item_uuid   = @ls_item-itemuuid AND
            header_object_type = @ls_item-headerobjecttype
      INTO TABLE @DATA(lt_simulate).

    IF ls_param-billextraflag = abap_false AND ls_param-account280 IS INITIAL.
      APPEND VALUE #( %tky = ls_item-%tky ) TO failed-item.

      APPEND VALUE #(  %tky = ls_item-%tky
                       %msg = new_message(
                                  id       = 'ZFI_PERIOD_MSG'
                                  number   = 029
                                  severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
    ENDIF.

    IF ls_param-documenttype IS INITIAL.
      APPEND VALUE #( %tky = ls_item-%tky ) TO failed-item.

      APPEND VALUE #(  %tky = ls_item-%tky
                       %msg = new_message(
                                  id       = 'ZFI_PERIOD_MSG'
                                  number   = 030
                                  severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
    ENDIF.

    IF ls_param-documentdate IS INITIAL OR ls_param-recorddate IS INITIAL.
      APPEND VALUE #( %tky = ls_item-%tky ) TO failed-item.

      APPEND VALUE #(  %tky = ls_item-%tky
                       %msg = new_message(
                                  id       = 'ZFI_PERIOD_MSG'
                                  number   = 031
                                  severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
    ENDIF.

    CHECK failed-item IS INITIAL.

    ls_jentry-%cid = 'cid_header'.
    ls_jentry-%param = VALUE #(  companycode                  = ls_header-companycode
                                 businesstransactiontype      = 'RFBU'
                                 accountingdocumenttype       = ls_param-documenttype
                                 accountingdocumentheadertext = ls_header-objectnumber
                                 createdbyuser                = cl_abap_context_info=>get_user_technical_name(  )
                                 documentreferenceid          = ls_header-objectnumber
                                 documentdate                 = ls_param-documentdate
                                 postingdate                  = ls_param-recorddate ).

    CLEAR ls_apitem.

    ls_apitem = VALUE #( glaccountlineitem = '001'
                         supplier          = ls_header-supplier
                         documentitemtext  = ls_header-headertext ).

    APPEND VALUE #( currencyrole = '00'
                    currency     = ls_item-currencycode
                    journalentryitemamount = ls_item-amount * -1 ) TO ls_apitem-_currencyamount.

    APPEND ls_apitem TO ls_jentry-%param-_apitems.

    LOOP AT lt_simulate INTO DATA(ls_simulate).
      IF ls_simulate-end_show_date(4) EQ ls_item-startdate(4).
        lv_sum_180 = lv_sum_180 + ls_simulate-period_amount.
      ELSE.
        lv_sum_280 = lv_sum_280 + ls_simulate-period_amount.
      ENDIF.
    ENDLOOP.

    IF lv_sum_180 IS NOT INITIAL.
      CLEAR ls_glitem.

      ls_glitem = VALUE #( glaccountlineitem = '002'
                           glaccount         = ls_item-mainaccount
                           documentitemtext  = ls_header-headertext ).

      APPEND VALUE #( currencyrole = '00'
                      currency     = ls_item-currencycode
                      journalentryitemamount = lv_sum_180 ) TO ls_glitem-_currencyamount.

      APPEND ls_glitem TO ls_jentry-%param-_glitems.
    ENDIF.

    IF lv_sum_280 IS NOT INITIAL.
      CLEAR ls_glitem.

      ls_glitem = VALUE #( glaccountlineitem = '003'
                           glaccount         = ls_param-account280
                           documentitemtext  = ls_header-headertext ).

      APPEND VALUE #( currencyrole = '00'
                      currency     = ls_item-currencycode
                      journalentryitemamount = lv_sum_280 ) TO ls_glitem-_currencyamount.

      APPEND ls_glitem TO ls_jentry-%param-_glitems.
    ENDIF.

    APPEND ls_jentry TO lt_jentry.
    lcl_buffer=>mt_jentry_bill = lt_jentry.
    lcl_buffer=>mt_key_bill = CORRESPONDING #( ls_key ).

    APPEND INITIAL LINE TO result ASSIGNING FIELD-SYMBOL(<fs_result>).
    <fs_result>-%tky = ls_item-%tky.
    <fs_result>-%param-headerobjecttype = ls_item-headerobjecttype.
    <fs_result>-%param-headeruuid = ls_item-headeruuid.
    <fs_result>-%param-itemuuid = ls_item-itemuuid.
  ENDMETHOD.

  METHOD getdefaultsforbill.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).

    LOOP AT lt_data INTO DATA(ls_data).
      INSERT VALUE #( %tky = ls_data-%tky ) INTO TABLE result REFERENCE INTO DATA(new_line).
      new_line->%param-billextraflag = ls_data-billextraflag.
      new_line->%param-documenttype  = 'KR'.
    ENDLOOP.
  ENDMETHOD.

  METHOD determinecreatebill.

  ENDMETHOD.

  METHOD update.
    DATA: period_item_log   TYPE STANDARD TABLE OF zfi_t_period_i,
          period_item_upd   TYPE STANDARD TABLE OF zfi_t_period_i,
          period_item_cntrl TYPE STANDARD TABLE OF zfi_s_cntrl_per_i.

    period_item_upd = CORRESPONDING #( entities MAPPING FROM ENTITY ).
    period_item_cntrl = CORRESPONDING #( entities MAPPING FROM ENTITY USING CONTROL ).

    SELECT * FROM zfi_t_period_i
    FOR ALL ENTRIES IN @entities
    WHERE header_uuid = @entities-headeruuid AND
          item_uuid = @entities-itemuuid AND
          header_object_type = @entities-headerobjecttype
      INTO TABLE @DATA(lt_item_old).

    LOOP AT period_item_upd ASSIGNING FIELD-SYMBOL(<fs_item_log>).
      READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
        ENTITY item
        ALL FIELDS  WITH VALUE #( ( headeruuid      = <fs_item_log>-header_uuid
                                   itemuuid         = <fs_item_log>-item_uuid
                                   headerobjecttype = <fs_item_log>-header_object_type ) )
        RESULT DATA(lt_item_2).

      READ TABLE period_item_cntrl INTO DATA(ls_cntrl) INDEX sy-tabix.
      READ TABLE lt_item_old INTO DATA(ls_item_old) WITH KEY header_uuid        = <fs_item_log>-header_uuid
                                                             item_uuid          = <fs_item_log>-item_uuid
                                                             header_object_type = <fs_item_log>-header_object_type.


      IF ls_cntrl-start_date IS NOT INITIAL.
        DATA(lv_start_date) = <fs_item_log>-start_date.
      ELSE.
        lv_start_date = ls_item_old-start_date.
      ENDIF.

      IF ls_cntrl-end_date IS NOT INITIAL.
        DATA(lv_end_date) = <fs_item_log>-end_date.
      ELSE.
        lv_end_date = ls_item_old-end_date.
      ENDIF.

      IF lv_start_date(4) EQ lv_end_date(4).
        <fs_item_log>-bill_extra_flag = abap_true.
      ELSE.
        <fs_item_log>-bill_extra_flag = abap_false.
      ENDIF.
    ENDLOOP.

    period_item_log = VALUE #(  FOR x = 1 WHILE x <= lines( lt_item_old )
                                  LET
                                    controlflagitem = VALUE #( period_item_cntrl[ x ] OPTIONAL )
                                    item_upd  = VALUE #( period_item_upd[ x ] OPTIONAL )
                                    item_old  = VALUE #( lt_item_old[ header_uuid        = item_upd-header_uuid
                                                                      header_object_type = item_upd-header_object_type
                                                                      item_uuid          = item_upd-item_uuid ] OPTIONAL )
                                  IN
                                  (
                                      header_uuid           = item_old-header_uuid
                                      item_uuid             = item_old-item_uuid
                                      header_object_type    = item_old-header_object_type
                                      amount                = COND #( WHEN controlflagitem-amount IS NOT INITIAL THEN item_upd-amount ELSE item_old-amount )
                                      document_type         = COND #( WHEN controlflagitem-document_type IS NOT INITIAL THEN item_upd-document_type ELSE item_old-document_type )
                                      currency_code         = COND #( WHEN controlflagitem-currency_code IS NOT INITIAL THEN item_upd-currency_code ELSE item_old-currency_code )
                                      item_object_type      = COND #( WHEN controlflagitem-item_object_type IS NOT INITIAL THEN item_upd-item_object_type ELSE item_old-item_object_type )
                                      rate_flag             = COND #( WHEN controlflagitem-rate_flag IS NOT INITIAL THEN item_upd-rate_flag ELSE item_old-rate_flag )
                                      start_date            = COND #( WHEN controlflagitem-start_date IS NOT INITIAL THEN item_upd-start_date ELSE item_old-start_date )
                                      end_date              = COND #( WHEN controlflagitem-end_date IS NOT INITIAL THEN item_upd-end_date ELSE item_old-end_date )
                                      cost_center           = COND #( WHEN controlflagitem-cost_center IS NOT INITIAL THEN item_upd-cost_center ELSE item_old-cost_center )
                                      wbs_element           = COND #( WHEN controlflagitem-wbs_element IS NOT INITIAL THEN item_upd-wbs_element ELSE item_old-wbs_element )
                                      main_account          = COND #( WHEN controlflagitem-main_account IS NOT INITIAL THEN item_upd-main_account ELSE item_old-main_account )
                                      cost_account          = COND #( WHEN controlflagitem-cost_account IS NOT INITIAL THEN item_upd-cost_account ELSE item_old-cost_account )
                                      vehicle_flag          = COND #( WHEN controlflagitem-vehicle_flag IS NOT INITIAL THEN item_upd-vehicle_flag ELSE item_old-vehicle_flag )
                                      ntde_account          = COND #( WHEN controlflagitem-ntde_account IS NOT INITIAL THEN item_upd-ntde_account ELSE item_old-ntde_account )
                                      day_flag              = COND #( WHEN controlflagitem-day_flag IS NOT INITIAL THEN item_upd-day_flag ELSE item_old-day_flag )
                                      month_flag            = COND #( WHEN controlflagitem-month_flag IS NOT INITIAL THEN item_upd-month_flag ELSE item_old-month_flag )
                                      bill_number           = item_upd-bill_number
                                      bill_year             = item_upd-bill_year
                                      bill_extra_flag       = item_upd-bill_extra_flag
                                      item_status           = COND #( WHEN controlflagitem-item_status IS NOT INITIAL THEN item_upd-item_status ELSE item_old-item_status )
                                      local_last_changed_at = COND #( WHEN controlflagitem-local_last_changed_at IS NOT INITIAL THEN item_upd-local_last_changed_at ELSE item_old-local_last_changed_at )
                                  )
                               ).

    LOOP AT period_item_log INTO DATA(ls_item_log).
      lcl_buffer=>simulate_all( EXPORTING is_item = ls_item_log ).
    ENDLOOP.

    lcl_buffer=>mt_item_log_update = period_item_log.
  ENDMETHOD.

  METHOD delete.
  ENDMETHOD.

  METHOD read.
    LOOP AT keys INTO DATA(ls_key).
      SELECT SINGLE * FROM zfi_i_period_i
        WHERE headeruuid EQ @ls_key-headeruuid
          AND headerobjecttype EQ @ls_key-headerobjecttype
          AND itemuuid EQ @ls_key-itemuuid
        INTO @DATA(ls_item).
      IF sy-subrc EQ 0.
        APPEND CORRESPONDING #( ls_item ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD rba_periodheader.
  ENDMETHOD.

  METHOD rba_periodsimulation.
  ENDMETHOD.

  METHOD cba_periodsimulation.
  ENDMETHOD.

  METHOD itemdefaultvalue.
    DATA: lt_data_item TYPE TABLE FOR UPDATE zfi_i_period_h\\item.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_item).
    LOOP AT lt_item ASSIGNING FIELD-SYMBOL(<fs_item>) WHERE itemcreateindicator = abap_false.
      SELECT SINGLE item_uuid FROM zfi_t_period_i
        WHERE header_uuid = @<fs_item>-headeruuid AND
              header_object_type = @<fs_item>-headerobjecttype AND
              item_uuid = @<fs_item>-itemuuid
        INTO @DATA(lv_exist_uuid).
      IF sy-subrc <> 0.
        <fs_item>-itemcreateindicator = abap_true.
        APPEND VALUE #( %tky                = <fs_item>-%tky
                        itemcreateindicator = <fs_item>-itemcreateindicator
                      ) TO lt_data_item.
      ENDIF.
    ENDLOOP.

    IF lt_data_item IS NOT INITIAL.
      MODIFY ENTITIES OF zfi_i_period_h IN LOCAL MODE
        ENTITY item
          UPDATE FIELDS ( itemcreateindicator )
          WITH CORRESPONDING #( lt_data_item ).
    ENDIF.
  ENDMETHOD.

  METHOD reversebill.
    DATA: lt_jreverse TYPE TABLE FOR ACTION IMPORT i_journalentrytp~reverse.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY header
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_header).

    CHECK lt_data IS NOT INITIAL.

    DATA(ls_header) = lt_header[ 1 ].
    DATA(ls_item) = lt_data[ 1 ].
    DATA(ls_key) = keys[ 1 ].

    SELECT SINGLE postingdate FROM i_journalentry
      WHERE accountingdocument = @ls_item-billnumber AND
            fiscalyear = @ls_item-billyear AND
            companycode = @ls_header-companycode
      INTO @DATA(lv_postingdate).

    APPEND INITIAL LINE TO lt_jreverse ASSIGNING FIELD-SYMBOL(<ls_jr>).
    <ls_jr>-companycode = ls_header-companycode.
    <ls_jr>-fiscalyear = ls_item-billyear.
    <ls_jr>-accountingdocument = ls_item-billnumber.
    <ls_jr>-%param = VALUE #( postingdate = lv_postingdate
                              reversalreason = '01'
                              createdbyuser = cl_abap_context_info=>get_user_technical_name(  ) ).

    lcl_buffer=>mt_bill_reverse = lt_jreverse.
    lcl_buffer=>mt_key_bill_rev = CORRESPONDING #( ls_key ).
  ENDMETHOD.

  METHOD validateDayCalc.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(daycalcdata).
    LOOP AT daycalcdata INTO DATA(ls_daycalc).
      DATA(lv_tabix) = sy-tabix.

      IF ls_daycalc-DayFlag = abap_false AND ls_daycalc-MonthFlag = abap_false.
        APPEND VALUE #( %tky = ls_daycalc-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_daycalc-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 033
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD validateMonthCalc.
    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY item
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(monthcalcdata).
    LOOP AT monthcalcdata INTO DATA(ls_monthcalcdata).
      DATA(lv_tabix) = sy-tabix.

      IF ls_monthcalcdata-MonthFlag = abap_false AND ls_monthcalcdata-DayFlag = abap_false.
        APPEND VALUE #( %tky = ls_monthcalcdata-%tky ) TO failed-item.

        APPEND VALUE #(  %tky        = ls_monthcalcdata-%tky
                         %msg        = new_message(
                                        id       = 'ZFI_PERIOD_MSG'
                                        number   = 033
                                        v1       = lv_tabix
                                        severity = if_abap_behv_message=>severity-error ) ) TO reported-item.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.

CLASS lhc_simulation DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR simulation RESULT result.

    METHODS get_global_features FOR GLOBAL FEATURES
      IMPORTING REQUEST requested_features FOR simulation RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR simulation RESULT result.

    METHODS reverse FOR MODIFY
      IMPORTING keys FOR ACTION simulation~reverse.
    METHODS update FOR MODIFY
      IMPORTING entities FOR UPDATE simulation.

    METHODS delete FOR MODIFY
      IMPORTING keys FOR DELETE simulation.

    METHODS read FOR READ
      IMPORTING keys FOR READ simulation RESULT result.

    METHODS rba_periodheader FOR READ
      IMPORTING keys_rba FOR READ simulation\_periodheader FULL result_requested RESULT result LINK association_links.

    METHODS rba_perioditem FOR READ
      IMPORTING keys_rba FOR READ simulation\_perioditem FULL result_requested RESULT result LINK association_links.

ENDCLASS.

CLASS lhc_simulation IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD get_global_features.
  ENDMETHOD.

  METHOD get_instance_features.

    CHECK keys IS NOT INITIAL.

    READ ENTITIES OF zfi_i_period_h IN LOCAL MODE
      ENTITY header
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_header).

    SELECT * FROM zfi_t_period_s
      FOR ALL ENTRIES IN @keys
      WHERE header_object_type = @keys-%key-headerobjecttype AND
            header_uuid        = @keys-%key-headeruuid AND
            item_uuid          = @keys-%key-itemuuid AND
            simulate_uuid      = @keys-%key-simulateuuid
      INTO TABLE @DATA(lt_simulate).

    result =
      VALUE #(
        FOR ls_key IN keys
          LET is_reversable  = COND #( WHEN ls_key-%is_draft = if_abap_behv=>mk-on OR
                                            lt_header[ 1 ]-status = 'ASK' OR
                                            lt_header[ 1 ]-status = 'IPT'
                                         THEN if_abap_behv=>fc-o-disabled
                                         ELSE if_abap_behv=>fc-o-enabled  )
          IN
            ( %tky-headerobjecttype = ls_key-headerobjecttype
              %tky-headeruuid       = ls_key-headeruuid
              %tky-itemuuid         = ls_key-itemuuid
              %tky-simulateuuid     = ls_key-simulateuuid
              %action-reverse       = is_reversable
              %is_draft             = ls_key-%is_draft
             ) ).

    LOOP AT result ASSIGNING FIELD-SYMBOL(<fs_result>).
      READ TABLE lt_simulate INTO DATA(ls_simulate) WITH KEY header_object_type = <fs_result>-headerobjecttype
                                                             header_uuid        = <fs_result>-headeruuid
                                                             item_uuid          = <fs_result>-itemuuid
                                                             simulate_uuid      = <fs_result>-simulateuuid.
      IF ls_simulate-simulate_comp = abap_false AND <fs_result>-%is_draft = if_abap_behv=>mk-off.
        <fs_result>-%action-reverse = if_abap_behv=>fc-o-disabled.
      ENDIF.
    ENDLOOP.
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
                                           ) TO reported-simulation.
      RETURN.
    ENDIF.

    IF ls_data-simulatevalid = abap_true.
      APPEND VALUE #(  %msg   = new_message( id       = 'ZFI_PERIOD_MSG'
                                             number   = 020
                                             severity = if_abap_behv_message=>severity-error
                                             v1       = lv_date_string
                                             v2       = ls_data-objectnumber
                                             v3       = ls_data-itemobjecttype )
                                           ) TO reported-simulation.
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
                                           ) TO reported-simulation.
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

    MODIFY ENTITIES OF i_journalentrytp PRIVILEGED
    ENTITY journalentry
    EXECUTE reverse FROM lt_jreverse
    FAILED DATA(ls_failed)
    REPORTED DATA(ls_reported)
    MAPPED DATA(ls_mapped).
    IF ls_failed IS INITIAL.
      lcl_buffer=>mt_mapped_reverse-journalentry = ls_mapped-journalentry.
      lcl_buffer=>mt_key_reverse = CORRESPONDING #( ls_key ).
    ELSE.
      LOOP AT ls_reported-journalentry INTO DATA(ls_reported_journalentry).
        APPEND VALUE #(  %msg             = ls_reported_journalentry-%msg
                         %state_area      = 'JOURNAL_REVERSE'
                         headeruuid       = ls_key-headeruuid
                         itemuuid         = ls_key-itemuuid
                         simulateuuid     = ls_key-simulateuuid
                         headerobjecttype = ls_key-headerobjecttype )
          TO reported-simulation.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD update.
  ENDMETHOD.

  METHOD delete.
  ENDMETHOD.

  METHOD read.
  ENDMETHOD.

  METHOD rba_periodheader.
  ENDMETHOD.

  METHOD rba_perioditem.
  ENDMETHOD.

ENDCLASS.

*CLASS lsc_zfi_i_period_h DEFINITION INHERITING FROM cl_abap_behavior_saver.
*  PROTECTED SECTION.
*
*    METHODS save_modified REDEFINITION.
*
*    METHODS cleanup_finalize REDEFINITION.
*
*ENDCLASS.
*
*CLASS lsc_zfi_i_period_h IMPLEMENTATION.
*
*  METHOD save_modified.
*    DATA: period_header_log     TYPE STANDARD TABLE OF zfi_t_period_h,
*          period_header_cntrl   TYPE STANDARD TABLE OF zfi_s_cntrl_per_h,
*          period_header_upd     TYPE STANDARD TABLE OF zfi_t_period_h,
*          period_item_log       TYPE STANDARD TABLE OF zfi_t_period_i,
*          period_item_cntrl     TYPE STANDARD TABLE OF zfi_s_cntrl_per_i,
*          period_item_upd       TYPE STANDARD TABLE OF zfi_t_period_i,
*          period_simulation_log TYPE STANDARD TABLE OF zfi_t_period_s.
*
*    IF lcl_buffer=>mt_mapped_bill IS NOT INITIAL.
*      LOOP AT lcl_buffer=>mt_mapped_bill-journalentry INTO DATA(ls_mapped_journalentry).
*        CONVERT KEY OF i_journalentrytp FROM ls_mapped_journalentry-%pid TO DATA(ls_key).
*
*        UPDATE zfi_t_period_i
*          SET bill_number = @ls_key-accountingdocument,
*              bill_year   = @ls_key-fiscalyear
*           WHERE header_uuid        = @lcl_buffer=>mt_key_bill-headeruuid AND
*                 item_uuid          = @lcl_buffer=>mt_key_bill-itemuuid AND
*                 header_object_type = @lcl_buffer=>mt_key_bill-headerobjecttype.
*      ENDLOOP.
*    ENDIF.
*
*    IF lcl_buffer=>mt_mapped_reverse IS NOT INITIAL.
*      LOOP AT lcl_buffer=>mt_mapped_reverse-journalentry INTO ls_mapped_journalentry.
*        CONVERT KEY OF i_journalentrytp FROM ls_mapped_journalentry-%pid TO ls_key.
*
*        SELECT SINGLE * FROM zfi_t_period_i
*          WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
*                item_uuid          = @lcl_buffer=>mt_key_reverse-itemuuid AND
*                header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype
*          INTO @DATA(ls_period_item).
*
*        SELECT * FROM zfi_t_period_s
*          WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
*                item_uuid          = @lcl_buffer=>mt_key_reverse-itemuuid AND
*                header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype
*          INTO TABLE @DATA(lt_period_upd).
*
*        READ TABLE lt_period_upd INTO DATA(ls_period_self) WITH KEY header_uuid        = lcl_buffer=>mt_key_reverse-headeruuid
*                                                                    item_uuid          = lcl_buffer=>mt_key_reverse-itemuuid
*                                                                    header_object_type = lcl_buffer=>mt_key_reverse-headerobjecttype
*                                                                    simulate_uuid      = lcl_buffer=>mt_key_reverse-simulateuuid.
*
*        SORT lt_period_upd BY end_show_date DESCENDING.
*
*        IF ls_period_self-nc_flag = abap_false.
*          LOOP AT lt_period_upd INTO DATA(ls_period_prev) WHERE end_show_date < ls_period_self-end_show_date AND
*                                                                simulate_comp = abap_true.
*            EXIT.
*          ENDLOOP.
*          IF sy-subrc = 0.
*            IF ls_period_item-rate_flag = abap_true.
*              SELECT SINGLE *
*                FROM zfi_i_period_curr_conv( p_amount      = @ls_period_self-period_amount,
*                                             p_source_curr = @ls_period_self-currency_code,
*                                             p_target_curr = 'TRY',
*                                             p_ratetype    = 'M',
*                                             p_date        = @ls_period_item-start_date )
*                INTO @DATA(ls_cur_prev_conv).
*              DATA(lv_cur_prev) = ls_cur_prev_conv-convertedamount.
*              DATA(lv_calc_date) = ls_period_item-start_date.
*            ELSE.
*              SELECT SINGLE *
*                FROM zfi_i_period_curr_conv( p_amount      = @ls_period_self-period_amount,
*                                             p_source_curr = @ls_period_self-currency_code,
*                                             p_target_curr = 'TRY',
*                                             p_ratetype    = 'M',
*                                             p_date        = @ls_period_prev-end_show_date )
*                INTO @ls_cur_prev_conv.
*              lv_cur_prev = ls_cur_prev_conv-convertedamount.
*              lv_calc_date = ls_period_prev-end_show_date.
*            ENDIF.
*          ELSE.
*            SELECT SINGLE *
*              FROM zfi_i_period_curr_conv( p_amount      = @ls_period_self-period_amount,
*                                           p_source_curr = @ls_period_self-currency_code,
*                                           p_target_curr = 'TRY',
*                                           p_ratetype    = 'M',
*                                           p_date        = @ls_period_item-start_date )
*              INTO @ls_cur_prev_conv.
*
*            lv_cur_prev = ls_cur_prev_conv-convertedamount.
*            lv_calc_date = ls_period_item-start_date.
*          ENDIF.
*        ELSE.
*          lv_cur_prev = ls_period_prev-period_amount.
*        ENDIF.
*
*        MODIFY lt_period_upd FROM VALUE #( document_number = space
*                                           document_year   = space
*                                           simulate_comp   = abap_false )
*          TRANSPORTING document_number document_year simulate_comp
*          WHERE simulate_uuid = lcl_buffer=>mt_key_reverse-simulateuuid AND
*                item_uuid   = lcl_buffer=>mt_key_reverse-itemuuid AND
*                header_uuid = lcl_buffer=>mt_key_reverse-headeruuid AND
*                header_object_type = lcl_buffer=>mt_key_reverse-headerobjecttype.
*
*        READ TABLE lt_period_upd INTO DATA(ls_period_upd) WITH KEY simulate_comp = abap_true.
*        IF sy-subrc = 0.
*          UPDATE zfi_t_period_i
*            SET item_status = 'DEV'
*             WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
*                   item_uuid          = @lcl_buffer=>mt_key_reverse-itemuuid AND
*                   header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype.
*
*          UPDATE zfi_t_period_h
*            SET status = 'BAS'
*             WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
*                   header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype.
*        ELSE.
*          UPDATE zfi_t_period_i
*            SET item_status = 'YRT'
*             WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
*                   item_uuid          = @lcl_buffer=>mt_key_reverse-itemuuid AND
*                   header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype.
*
*          SELECT * FROM zfi_t_period_i
*            WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
*                  header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype
*            INTO TABLE @DATA(lt_period_item_upd).
*
*          MODIFY lt_period_item_upd FROM VALUE #( item_status = 'YRT' )
*            TRANSPORTING item_status
*            WHERE item_uuid   = lcl_buffer=>mt_key_reverse-itemuuid AND
*                  header_uuid = lcl_buffer=>mt_key_reverse-headeruuid AND
*                  header_object_type = lcl_buffer=>mt_key_reverse-headerobjecttype.
*
*          LOOP AT lt_period_item_upd INTO DATA(ls_period_item_upd) WHERE item_status <> 'YRT'.
*            EXIT.
*          ENDLOOP.
*          IF sy-subrc <> 0.
*            UPDATE zfi_t_period_h
*              SET status = 'BAS'
*               WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
*                     header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype.
*          ENDIF.
*        ENDIF.
*
*        UPDATE zfi_t_period_s
*          SET document_number = @space,
*              document_year   = @space,
*              simulate_comp   = @abap_false,
*              nc_amount       = @lv_cur_prev
*           WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
*                 item_uuid          = @lcl_buffer=>mt_key_reverse-itemuuid AND
*                 simulate_uuid      = @lcl_buffer=>mt_key_reverse-simulateuuid AND
*                 header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype.
*
*        IF ls_period_self-nc_flag = abap_false.
*          LOOP AT lt_period_upd ASSIGNING FIELD-SYMBOL(<fs_period_up>) WHERE simulate_uuid <> lcl_buffer=>mt_key_reverse-simulateuuid AND
*                                                                             simulate_comp = abap_false.
*            SELECT SINGLE *
*              FROM zfi_i_period_curr_conv( p_amount      = @<fs_period_up>-period_amount,
*                                           p_source_curr = @<fs_period_up>-currency_code,
*                                           p_target_curr = 'TRY',
*                                           p_ratetype    = 'M',
*                                           p_date        = @lv_calc_date )
*              INTO @DATA(ls_cur_conv).
*
*            UPDATE zfi_t_period_s
*              SET nc_amount       = @ls_cur_conv-convertedamount
*               WHERE header_uuid        = @<fs_period_up>-header_uuid AND
*                     item_uuid          = @<fs_period_up>-item_uuid AND
*                     simulate_uuid      = @<fs_period_up>-simulate_uuid AND
*                     header_object_type = @<fs_period_up>-header_object_type.
*          ENDLOOP.
*        ENDIF.
*      ENDLOOP.
*    ENDIF.
*
*    IF create-header IS NOT INITIAL.
*      period_header_log = CORRESPONDING #( create-header MAPPING FROM ENTITY ).
*
*      DATA(lv_object_type) = period_header_log[ 1 ]-header_object_type.
*
*      SELECT SINGLE number_range_no FROM zfi_t_obj_type_h
*        WHERE header_object_type = @lv_object_type
*        INTO @DATA(lv_number_range_no).
*
*      TRY.
*          cl_numberrange_runtime=>number_get(
*            EXPORTING
*              nr_range_nr       = lv_number_range_no
*              object            = 'ZFI_OBJ_NO'
*              quantity          = 1
*            IMPORTING
*              number            = DATA(lv_number)
*              returncode        = DATA(lv_return_code)
*              returned_quantity = DATA(lv_return_quan)
*          ).
*        CATCH cx_number_ranges INTO DATA(lx_number_ranges).
*      ENDTRY.
*
*      DATA(lv_string_num) = CONV string( lv_number ).
*      lv_string_num = |{ lv_string_num ALPHA = OUT }|.
*
*      period_header_log[ 1 ]-status = 'BAS'.
*      period_header_log[ 1 ]-object_number = lv_string_num.
*
*      INSERT zfi_t_period_h FROM TABLE @period_header_log.
*    ENDIF.
*
*    IF create-item IS NOT INITIAL.
*      period_item_log = CORRESPONDING #( create-item MAPPING FROM ENTITY ).
*      LOOP AT period_item_log ASSIGNING FIELD-SYMBOL(<fs_item_log>).
*        <fs_item_log>-item_status = 'YRT'.
*
*        IF <fs_item_log>-end_date(4) EQ <fs_item_log>-start_date(4).
*          <fs_item_log>-bill_extra_flag = abap_true.
*        ENDIF.
*      ENDLOOP.
*      INSERT zfi_t_period_i FROM TABLE @period_item_log.
*
*      LOOP AT create-item INTO DATA(ls_cre_item).
*        lcl_buffer=>simulate_all( EXPORTING iv_header_object_type = ls_cre_item-headerobjecttype
*                                            iv_header_uuid        = ls_cre_item-headeruuid
*                                            iv_item_uuid          = ls_cre_item-itemuuid ).
*      ENDLOOP.
*    ENDIF.
*
*    IF update-header IS NOT INITIAL.
*      period_header_upd = CORRESPONDING #( update-header MAPPING FROM ENTITY ).
*      period_header_cntrl = CORRESPONDING #( update-header MAPPING FROM ENTITY USING CONTROL ).
*
*      SELECT * FROM zfi_t_period_h
*      FOR ALL ENTRIES IN @update-header
*      WHERE header_uuid = @update-header-headeruuid AND
*            header_object_type = @update-header-headerobjecttype
*        INTO TABLE @DATA(lt_header_old).
*
*      period_header_log = VALUE #(  FOR x = 1 WHILE x <= lines( lt_header_old )
*                                    LET
*                                      controlflag = VALUE #( period_header_cntrl[ x ] OPTIONAL )
*                                      header_upd  = VALUE #( period_header_upd[ x ] OPTIONAL )
*                                      header_old  = VALUE #( lt_header_old[ header_uuid        = header_upd-header_uuid
*                                                                            header_object_type = header_upd-header_object_type ] OPTIONAL )
*                                    IN
*                                    (
*                                        header_uuid           = header_old-header_uuid
*                                        header_object_type    = header_old-header_object_type
*                                        object_number         = header_old-object_number
*                                        company_code          = COND #( WHEN controlflag-company_code IS NOT INITIAL THEN header_upd-company_code ELSE header_old-company_code )
*                                        supplier              = COND #( WHEN controlflag-supplier IS NOT INITIAL THEN header_upd-supplier ELSE header_old-supplier )
*                                        status                = COND #( WHEN controlflag-status IS NOT INITIAL THEN header_upd-status ELSE header_old-status )
*                                        header_text           = COND #( WHEN controlflag-header_text IS NOT INITIAL THEN header_upd-header_text ELSE header_old-header_text )
*                                        local_last_changed_at = COND #( WHEN controlflag-local_last_changed_at IS NOT INITIAL THEN header_upd-local_last_changed_at ELSE header_old-local_last_changed_at )
*                                    )
*                                 ).
*      MODIFY zfi_t_period_h FROM TABLE @period_header_log.
*    ENDIF.
*
*    IF update-item IS NOT INITIAL.
*      period_item_upd = CORRESPONDING #( update-item MAPPING FROM ENTITY ).
*      period_item_cntrl = CORRESPONDING #( update-item MAPPING FROM ENTITY USING CONTROL ).
*
*      SELECT * FROM zfi_t_period_i
*      FOR ALL ENTRIES IN @update-item
*      WHERE header_uuid = @update-item-headeruuid AND
*            item_uuid = @update-item-itemuuid AND
*            header_object_type = @update-item-headerobjecttype
*        INTO TABLE @DATA(lt_item_old).
*
*      LOOP AT period_item_upd ASSIGNING <fs_item_log>.
*        READ TABLE period_item_cntrl INTO DATA(ls_cntrl) INDEX sy-tabix.
*        READ TABLE lt_item_old INTO DATA(ls_item_old) WITH KEY header_uuid        = <fs_item_log>-header_uuid
*                                                               item_uuid          = <fs_item_log>-item_uuid
*                                                               header_object_type = <fs_item_log>-header_object_type.
*
*
*        IF ls_cntrl-start_date IS NOT INITIAL.
*          DATA(lv_start_date) = <fs_item_log>-start_date.
*        ELSE.
*          lv_start_date = ls_item_old-start_date.
*        ENDIF.
*
*        IF ls_cntrl-end_date IS NOT INITIAL.
*          DATA(lv_end_date) = <fs_item_log>-end_date.
*        ELSE.
*          lv_end_date = ls_item_old-end_date.
*        ENDIF.
*
*        IF lv_start_date(4) EQ lv_end_date(4).
*          <fs_item_log>-bill_extra_flag = abap_true.
*        ELSE.
*          <fs_item_log>-bill_extra_flag = abap_false.
*        ENDIF.
*      ENDLOOP.
*
*      period_item_log = VALUE #(  FOR x = 1 WHILE x <= lines( lt_item_old )
*                                    LET
*                                      controlflagitem = VALUE #( period_item_cntrl[ x ] OPTIONAL )
*                                      item_upd  = VALUE #( period_item_upd[ x ] OPTIONAL )
*                                      item_old  = VALUE #( lt_item_old[ header_uuid        = item_upd-header_uuid
*                                                                        header_object_type = item_upd-header_object_type
*                                                                        item_uuid          = item_upd-item_uuid ] OPTIONAL )
*                                    IN
*                                    (
*                                        header_uuid           = item_old-header_uuid
*                                        item_uuid             = item_old-item_uuid
*                                        header_object_type    = item_old-header_object_type
*                                        amount                = COND #( WHEN controlflagitem-amount IS NOT INITIAL THEN item_upd-amount ELSE item_old-amount )
*                                        document_type         = COND #( WHEN controlflagitem-document_type IS NOT INITIAL THEN item_upd-document_type ELSE item_old-document_type )
*                                        currency_code         = COND #( WHEN controlflagitem-currency_code IS NOT INITIAL THEN item_upd-currency_code ELSE item_old-currency_code )
*                                        item_object_type      = COND #( WHEN controlflagitem-item_object_type IS NOT INITIAL THEN item_upd-item_object_type ELSE item_old-item_object_type )
*                                        rate_flag             = COND #( WHEN controlflagitem-rate_flag IS NOT INITIAL THEN item_upd-rate_flag ELSE item_old-rate_flag )
*                                        start_date            = COND #( WHEN controlflagitem-start_date IS NOT INITIAL THEN item_upd-start_date ELSE item_old-start_date )
*                                        end_date              = COND #( WHEN controlflagitem-end_date IS NOT INITIAL THEN item_upd-end_date ELSE item_old-end_date )
*                                        cost_center           = COND #( WHEN controlflagitem-cost_center IS NOT INITIAL THEN item_upd-cost_center ELSE item_old-cost_center )
*                                        wbs_element           = COND #( WHEN controlflagitem-wbs_element IS NOT INITIAL THEN item_upd-wbs_element ELSE item_old-wbs_element )
*                                        main_account          = COND #( WHEN controlflagitem-main_account IS NOT INITIAL THEN item_upd-main_account ELSE item_old-main_account )
*                                        cost_account          = COND #( WHEN controlflagitem-cost_account IS NOT INITIAL THEN item_upd-cost_account ELSE item_old-cost_account )
*                                        vehicle_flag          = COND #( WHEN controlflagitem-vehicle_flag IS NOT INITIAL THEN item_upd-vehicle_flag ELSE item_old-vehicle_flag )
*                                        ntde_account          = COND #( WHEN controlflagitem-ntde_account IS NOT INITIAL THEN item_upd-ntde_account ELSE item_old-ntde_account )
*                                        day_flag              = COND #( WHEN controlflagitem-day_flag IS NOT INITIAL THEN item_upd-day_flag ELSE item_old-day_flag )
*                                        month_flag            = COND #( WHEN controlflagitem-month_flag IS NOT INITIAL THEN item_upd-month_flag ELSE item_old-month_flag )
*                                        bill_extra_flag       = item_upd-bill_extra_flag
*                                        item_status           = COND #( WHEN controlflagitem-item_status IS NOT INITIAL THEN item_upd-item_status ELSE item_old-item_status )
*                                        local_last_changed_at = COND #( WHEN controlflagitem-local_last_changed_at IS NOT INITIAL THEN item_upd-local_last_changed_at ELSE item_old-local_last_changed_at )
*                                    )
*                                 ).
*      MODIFY zfi_t_period_i FROM TABLE @period_item_log.
*
*      LOOP AT update-item INTO DATA(ls_upd_item).
*        lcl_buffer=>simulate_all( EXPORTING iv_header_object_type = ls_upd_item-headerobjecttype
*                                            iv_header_uuid        = ls_upd_item-headeruuid
*                                            iv_item_uuid          = ls_upd_item-itemuuid ).
*      ENDLOOP.
*    ENDIF.
*
*    IF lcl_buffer=>mt_buf_sim_cre IS NOT INITIAL.
*      INSERT zfi_t_period_s FROM TABLE @lcl_buffer=>mt_buf_sim_cre.
*    ENDIF.
*
*    IF lcl_buffer=>mt_buf_sim_del IS NOT INITIAL.
*      DELETE zfi_t_period_s FROM TABLE @lcl_buffer=>mt_buf_sim_del.
*    ENDIF.
*  ENDMETHOD.
*
*  METHOD cleanup_finalize.
*  ENDMETHOD.
*
*ENDCLASS.
CLASS lsc_zfi_i_period_h DEFINITION INHERITING FROM cl_abap_behavior_saver.

  PROTECTED SECTION.

    METHODS finalize REDEFINITION.

    METHODS check_before_save REDEFINITION.

    METHODS cleanup REDEFINITION.

    METHODS cleanup_finalize REDEFINITION.

    METHODS save REDEFINITION.
ENDCLASS.

CLASS lsc_zfi_i_period_h IMPLEMENTATION.

  METHOD finalize.
    IF lcl_buffer=>mt_jentry_bill IS NOT INITIAL.
      MODIFY ENTITIES OF i_journalentrytp
            ENTITY journalentry
           EXECUTE post
              FROM lcl_buffer=>mt_jentry_bill
            MAPPED DATA(ls_mapped)
            FAILED DATA(ls_failed)
          REPORTED DATA(ls_reported).

      IF ls_failed IS INITIAL.
        lcl_buffer=>mt_mapped_bill-journalentry = ls_mapped-journalentry.
      ELSE.
        LOOP AT ls_reported-journalentry INTO DATA(ls_reported_journalentry).
          APPEND VALUE #(  %msg             = ls_reported_journalentry-%msg
                           %state_area      = 'BILL_POST'
                           headeruuid       = lcl_buffer=>mt_key_bill-headeruuid
                           itemuuid         = lcl_buffer=>mt_key_bill-itemuuid
                           headerobjecttype = lcl_buffer=>mt_key_bill-headerobjecttype )
            TO reported-item.
        ENDLOOP.
      ENDIF.
    ENDIF.

    IF lcl_buffer=>mt_bill_reverse IS NOT INITIAL.
      MODIFY ENTITIES OF i_journalentrytp PRIVILEGED
      ENTITY journalentry
      EXECUTE reverse FROM lcl_buffer=>mt_bill_reverse
      FAILED ls_failed
      REPORTED ls_reported
      MAPPED ls_mapped.
      IF ls_failed IS INITIAL.
        lcl_buffer=>mt_mapped_rev_bill-journalentry = ls_mapped-journalentry.
      ELSE.
        LOOP AT ls_reported-journalentry INTO ls_reported_journalentry.
          APPEND VALUE #(  %msg             = ls_reported_journalentry-%msg
                           %state_area      = 'BILL_REVERSE'
                           headeruuid       = lcl_buffer=>mt_key_bill_rev-headeruuid
                           itemuuid         = lcl_buffer=>mt_key_bill_rev-itemuuid
                           headerobjecttype = lcl_buffer=>mt_key_bill_rev-headerobjecttype )
            TO reported-item.
        ENDLOOP.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD check_before_save.
  ENDMETHOD.

  METHOD cleanup.
  ENDMETHOD.

  METHOD cleanup_finalize.
  ENDMETHOD.

  METHOD save.
    IF lcl_buffer=>mt_header_log_create IS NOT INITIAL.
      INSERT zfi_t_period_h FROM TABLE @lcl_buffer=>mt_header_log_create.
    ENDIF.

    IF lcl_buffer=>mt_header_log_update IS NOT INITIAL.
      MODIFY zfi_t_period_h FROM TABLE @lcl_buffer=>mt_header_log_update.
    ENDIF.

    IF lcl_buffer=>mt_item_log_create IS NOT INITIAL.
      INSERT zfi_t_period_i FROM TABLE @lcl_buffer=>mt_item_log_create.
    ENDIF.

    IF lcl_buffer=>mt_item_log_update IS NOT INITIAL.
      MODIFY zfi_t_period_i FROM TABLE @lcl_buffer=>mt_item_log_update.
    ENDIF.

    IF lcl_buffer=>mt_buf_sim_cre IS NOT INITIAL.
      INSERT zfi_t_period_s FROM TABLE @lcl_buffer=>mt_buf_sim_cre.
    ENDIF.

    IF lcl_buffer=>mt_buf_sim_del IS NOT INITIAL.
      DELETE zfi_t_period_s FROM TABLE @lcl_buffer=>mt_buf_sim_del.
    ENDIF.

    IF lcl_buffer=>mt_mapped_bill IS NOT INITIAL.
      LOOP AT lcl_buffer=>mt_mapped_bill-journalentry INTO DATA(ls_mapped_journalentry).
        CONVERT KEY OF i_journalentrytp FROM ls_mapped_journalentry-%pid TO DATA(ls_key).

        UPDATE zfi_t_period_i
          SET bill_number = @ls_key-accountingdocument,
              bill_year   = @ls_key-fiscalyear
           WHERE header_uuid        = @lcl_buffer=>mt_key_bill-headeruuid AND
                 item_uuid          = @lcl_buffer=>mt_key_bill-itemuuid AND
                 header_object_type = @lcl_buffer=>mt_key_bill-headerobjecttype.
      ENDLOOP.
    ENDIF.

    IF lcl_buffer=>mt_mapped_rev_bill IS NOT INITIAL.
      LOOP AT lcl_buffer=>mt_mapped_rev_bill-journalentry INTO ls_mapped_journalentry.
        CONVERT KEY OF i_journalentrytp FROM ls_mapped_journalentry-%pid TO ls_key.

        UPDATE zfi_t_period_i
          SET bill_number = @space,
              bill_year   = @space
           WHERE header_uuid        = @lcl_buffer=>mt_key_bill_rev-headeruuid AND
                 item_uuid          = @lcl_buffer=>mt_key_bill_rev-itemuuid AND
                 header_object_type = @lcl_buffer=>mt_key_bill_rev-headerobjecttype.
      ENDLOOP.
    ENDIF.

    IF lcl_buffer=>mt_mapped_reverse IS NOT INITIAL.
      LOOP AT lcl_buffer=>mt_mapped_reverse-journalentry INTO ls_mapped_journalentry.
        CONVERT KEY OF i_journalentrytp FROM ls_mapped_journalentry-%pid TO ls_key.

        SELECT SINGLE * FROM zfi_t_period_i
          WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
                item_uuid          = @lcl_buffer=>mt_key_reverse-itemuuid AND
                header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype
          INTO @DATA(ls_period_item).

        SELECT * FROM zfi_t_period_s
          WHERE header_uuid        = @lcl_buffer=>mt_key_reverse-headeruuid AND
                item_uuid          = @lcl_buffer=>mt_key_reverse-itemuuid AND
                header_object_type = @lcl_buffer=>mt_key_reverse-headerobjecttype
          INTO TABLE @DATA(lt_period_upd).

        READ TABLE lt_period_upd INTO DATA(ls_period_self) WITH KEY header_uuid        = lcl_buffer=>mt_key_reverse-headeruuid
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
              DATA(lv_calc_date) = ls_period_item-start_date.
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

        READ TABLE lt_period_upd INTO DATA(ls_period_upd) WITH KEY simulate_comp = abap_true.
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
            INTO TABLE @DATA(lt_period_item_upd).

          MODIFY lt_period_item_upd FROM VALUE #( item_status = 'YRT' )
            TRANSPORTING item_status
            WHERE item_uuid   = lcl_buffer=>mt_key_reverse-itemuuid AND
                  header_uuid = lcl_buffer=>mt_key_reverse-headeruuid AND
                  header_object_type = lcl_buffer=>mt_key_reverse-headerobjecttype.

          LOOP AT lt_period_item_upd INTO DATA(ls_period_item_upd) WHERE item_status <> 'YRT'.
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
          LOOP AT lt_period_upd ASSIGNING FIELD-SYMBOL(<fs_period_up>) WHERE simulate_uuid <> lcl_buffer=>mt_key_reverse-simulateuuid AND
                                                                             simulate_comp = abap_false.
            SELECT SINGLE *
              FROM zfi_i_period_curr_conv( p_amount      = @<fs_period_up>-period_amount,
                                           p_source_curr = @<fs_period_up>-currency_code,
                                           p_target_curr = 'TRY',
                                           p_ratetype    = 'M',
                                           p_date        = @lv_calc_date )
              INTO @DATA(ls_cur_conv).

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

ENDCLASS.
