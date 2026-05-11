@AbapCatalog.sqlViewName: 'ZFI_I_PER_CUR'
@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Dönemselleştirme Kur Dönüşümü View CDS'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #XL,
    dataClass: #MIXED
}
define view ZFI_I_PERIOD_CURR_CONV
  with parameters
    p_ratetype    : kurst,
    p_source_curr : waers,
    p_target_curr : waers,
    p_date        : abap.dats,
    p_amount      : ukm_parameter_value_amount
  as select from I_ExchangeRateRawData
{
  key ''                                                                                           as dummy,
      @Semantics.currencyCode: true
      $parameters.p_target_curr                                                                    as CurrencyCode,
      @Semantics.amount.currencyCode: 'CurrencyCode'
      cast (currency_conversion(
        client => $session.client,
        amount => $parameters.p_amount,
        round => '',
        source_currency => $parameters.p_source_curr,
        target_currency => $parameters.p_target_curr,
        exchange_rate_type => $parameters.p_ratetype,
        exchange_rate_date => $parameters.p_date ) as ukm_parameter_value_amount preserving type ) as ConvertedAmount
}
