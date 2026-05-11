@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Dönemselleştirme Kalem View CDS'
@Metadata.ignorePropagatedAnnotations: true
@Metadata.allowExtensions: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #L,
    dataClass: #MIXED
}
define view entity ZFI_I_PERIOD_I
  as select from zfi_t_period_i
  association [0..1] to I_CostCenterText      as _CostCenterText on  $projection.CostCenter       = _CostCenterText.CostCenter
                                                                 and '99991231'                   = _CostCenterText.ValidityEndDate
                                                                 and 'A000'                       = _CostCenterText.ControllingArea
                                                                 and _CostCenterText.Language     = $session.system_language
  association to parent ZFI_I_PERIOD_H        as _PeriodHeader   on  $projection.HeaderUuid       = _PeriodHeader.HeaderUuid
                                                                 and $projection.HeaderObjectType = _PeriodHeader.HeaderObjectType
  composition [0..*] of ZFI_I_PERIOD_S        as _PeriodSimulation
{
  key header_uuid           as HeaderUuid,
  key item_uuid             as ItemUuid,
  key header_object_type    as HeaderObjectType,
      item_object_type      as ItemObjectType,
      @Semantics.amount.currencyCode: 'CurrencyCode'
      amount                as Amount,
      currency_code         as CurrencyCode,
      start_date            as StartDate,
      end_date              as EndDate,
      @ObjectModel.text.control: #ASSOCIATED_TEXT_UI_HIDDEN
      @ObjectModel.text.association: '_CostCenterText'
      cost_center           as CostCenter,
      wbs_element           as WbsElement,
      main_account          as MainAccount,
      cost_account          as CostAccount,
      document_type         as DocumentType,
      vehicle_flag          as VehicleFlag,
      ntde_account          as NtdeAccount,
      day_flag              as DayFlag,
      month_flag            as MonthFlag,
      bill_number           as BillNumber,
      bill_year             as BillYear,
      bill_extra_flag       as BillExtraFlag,
      rate_flag             as RateFlag,
      item_status           as ItemStatus,
      cast ( case item_status
        when 'YRT' then 'Yaratıldı'
        when 'DEV' then 'Devam Ediyor'
        when 'TAM' then 'Bitirildi'
        else ''
       end as abap.char( 30 ) ) as ItemStatusText,
      cast ( case item_status
        when 'YRT' then '2'
        when 'DEV' then '2'
        when 'TAM' then '3'
        else ''
       end as zfi_e_char preserving type ) as ItemStatusCriticality,
      cast('' as abap_boolean preserving type ) as ItemCreateIndicator, 
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,
      @ObjectModel.filter.enabled: false
      _CostCenterText,
      _PeriodHeader,
      _PeriodSimulation
}
