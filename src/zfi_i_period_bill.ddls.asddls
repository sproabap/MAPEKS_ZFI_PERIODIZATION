@EndUserText.label: 'Dönemselleştirme Fatura Kaydı Abstra CDS'
define root abstract entity ZFI_I_PERIOD_BILL
{
  @EndUserText.label : 'Belge Tarihi'
  DocumentDate  : zfi_e_period_start_date;
  @EndUserText.label : 'Kayıt Tarihi'
  RecordDate    : zfi_e_period_start_date;
  @Consumption.valueHelpDefinition: [{ entity: { name: 'I_AccountingDocumentType', element: 'AccountingDocumentType'} }]
  @Consumption.filter.multipleSelections: false
  @Consumption.filter.selectionType: #SINGLE
  DocumentType  : blart;
  @Consumption.valueHelpDefinition: [{ entity: { name: 'ZFI_I_GLACCOUNT', element: 'GLAccount'} }]
  @EndUserText.label : '280 Hesap'
  @UI.hidden    : #(BillExtraFlag)
  Account280    : zfi_e_saknr;
  @UI.hidden    : true
  BillExtraFlag : abap_boolean;
}
