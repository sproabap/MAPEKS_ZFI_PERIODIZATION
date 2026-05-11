@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Dönemselleştirme Simülasyon View CDS'
@Metadata.ignorePropagatedAnnotations: true
@Metadata.allowExtensions: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #L,
    dataClass: #MIXED
}
define view entity ZFI_I_PERIOD_S
  as select from zfi_t_period_s
  association to parent ZFI_I_PERIOD_I as _PeriodItem   on  $projection.ItemUuid         = _PeriodItem.ItemUuid
                                                        and $projection.HeaderUuid       = _PeriodItem.HeaderUuid
                                                        and $projection.HeaderObjectType = _PeriodItem.HeaderObjectType
  association to ZFI_I_PERIOD_H        as _PeriodHeader on  $projection.HeaderUuid       = _PeriodHeader.HeaderUuid
                                                        and $projection.HeaderObjectType = _PeriodHeader.HeaderObjectType
{
  key header_uuid           as HeaderUuid,
  key item_uuid             as ItemUuid,
  key simulate_uuid         as SimulateUuid,
  key header_object_type    as HeaderObjectType,
      start_calc_date       as StartCalcDate,
      end_calc_date         as EndCalcDate,
      start_show_date       as StartShowDate,
      end_show_date         as EndShowDate,
      @Semantics.amount.currencyCode: 'CurrencyCode'
      balance_amount        as BalanceAmount,
      @Semantics.amount.currencyCode: 'CurrencyCode'
      period_amount         as PeriodAmount,
      @Semantics.amount.currencyCode: 'CurrencyCode'
      remaining_amount      as RemainingAmount,
      @Semantics.amount.currencyCode: 'NcCurrency'
      nc_amount             as NcAmount,
      currency_code         as CurrencyCode,
      nc_currency           as NcCurrency,
      document_number       as DocumentNumber,
      document_year         as DocumentYear,
      simulate_comp         as SimulateComp,
      simulate_valid        as SimulateValid,
      nc_flag               as NcFlag,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,
      _PeriodItem,
      _PeriodHeader
}
