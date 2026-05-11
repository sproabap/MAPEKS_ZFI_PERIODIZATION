@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Dönemselleştirme Başlık View CDS'
@Metadata.ignorePropagatedAnnotations: true
@Metadata.allowExtensions: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #L,
    dataClass: #MIXED
}
define root view entity ZFI_I_PERIOD_H
  as select from zfi_t_period_h
  association [0..1] to I_Supplier       as _Supplier    on $projection.Supplier = _Supplier.Supplier
  association [0..1] to I_CompanyCode    as _CompanyCode on $projection.CompanyCode = _CompanyCode.CompanyCode
  association [0..1] to ZFI_I_OBJ_TYPE_H as _ObjTypeH    on $projection.HeaderObjectType = _ObjTypeH.HeaderObjectType
  composition [0..*] of ZFI_I_PERIOD_I   as _PeriodItem
{
  key header_uuid           as HeaderUuid,
      @ObjectModel.text.control: #ASSOCIATED_TEXT_UI_HIDDEN
      @ObjectModel.text.association: '_ObjTypeH'
  key header_object_type    as HeaderObjectType,
      @ObjectModel.text.control: #ASSOCIATED_TEXT_UI_HIDDEN
      @ObjectModel.text.association: '_CompanyCode'
      company_code          as CompanyCode,
      @ObjectModel.text.control: #ASSOCIATED_TEXT_UI_HIDDEN
      @ObjectModel.text.association: '_Supplier'
      supplier              as Supplier,
      header_text           as HeaderText,
      status                as Status,
      object_number         as ObjectNumber,
      cast ( case status
        when 'BAS' then 'Başlatıldı'
        when 'TAM' then 'Tamamlandı'
        when 'ASK' then 'Askıya alındı'
        when 'IPT' then 'İptal Edildi'
        else ''
       end as abap.char( 30 ) ) as StatusText,
      cast ( case status
        when 'BAS' then '2'
        when 'TAM' then '3'
        when 'ASK' then '1'
        when 'IPT' then '1'
        else ''
       end as zfi_e_char preserving type ) as StatusCriticality,
      cast('' as abap_boolean preserving type ) as CreateIndicator,       
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,
      @ObjectModel.filter.enabled: false
      _Supplier,
      @ObjectModel.filter.enabled: false
      _CompanyCode,
      @ObjectModel.filter.enabled: false
      _ObjTypeH,
      _PeriodItem
}
