@EndUserText.label: 'Dönemselleştirme Gider Kaydı Custom CDS'
@ObjectModel.query.implementedBy: 'ABAP:ZFI_CL_PERIOD_REQ'
@UI.headerInfo: {
    typeName: 'Kayıt',
    typeNamePlural: 'Kayıt',
    title: {
        type: #STANDARD,
        label: 'Kayıt',
        value: 'Identifier'
    },
    description: {
        type: #STANDARD,
        value: 'ItemObjectType'
    }
}
define root custom entity ZFI_I_PERIOD_RECORD
{
//      @UI.lineItem     : [{ type: #FOR_ACTION, dataAction: 'accounting', label: 'Muhasebeleştir' }]
      @UI.facet        : [ { id:              'DetailInfo',
                             purpose:         #STANDARD,
                             type:            #IDENTIFICATION_REFERENCE,
                             label:           'Detay',
                             position:        10 } ]

      @UI.hidden       : true
  key HeaderUuid       : sysuuid_x16;
      @UI.hidden       : true
  key ItemUuid         : sysuuid_x16;
      @UI.hidden       : true
  key SimulateUuid     : sysuuid_x16;
      @UI.hidden       : true
  key KeyDate          : datum;
      @UI              : {  lineItem:       [ { position: 20 } ],
                            selectionField: [ { position: 20 } ],
                            identification: [ { position: 20 } ] }
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZFI_I_OBJ_TYPE_H', element: 'HeaderObjectType'} }]
  key HeaderObjectType : zfi_e_header_object_type;
      @UI              : {  lineItem:       [ { position: 10 } ],
                            selectionField: [ { position: 10 } ],
                            identification: [ { position: 10 } ] }
      ObjectNumber     : zfi_e_obj_no;
      @UI              : {  lineItem:       [ { position: 30 } ],
                            selectionField: [ { position: 30 } ],
                            identification: [ { position: 30 } ] }
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZFI_I_OBJ_TYPE_I', element: 'ItemObjectType'},
                                           additionalBinding: [{ localElement: 'HeaderObjectType', element: 'HeaderObjectType', usage: #FILTER }] }]
      ItemObjectType   : zfi_e_item_object_type;
      @UI              : { lineItem:        [ { position: 40 } ],
                           selectionField:  [ { position: 40 } ],
                           identification:  [ { position: 40 } ] }
      @Consumption.valueHelpDefinition: [{ entity: { name: 'I_CompanyCodeVH', element: 'CompanyCode'} }]
      @Consumption.filter.mandatory: true
      @Consumption.filter.multipleSelections: false
      @Consumption.filter.selectionType: #SINGLE
      CompanyCode      : bukrs;
      @UI              : { lineItem:        [ { position: 50, label: 'Dönemselleştirme Tarihi' } ],
                           selectionField:  [ { position: 50 } ],
                           identification:  [ { position: 50, label: 'Dönemselleştirme Tarihi' } ] }
      @Consumption.filter.mandatory: true
      @Consumption.filter.multipleSelections: false
      @Consumption.filter.selectionType: #SINGLE
      @EndUserText.label:'Anahtar Tarih'
      EndShowDate      : zfi_e_period_end_date;
      @UI              : { lineItem:        [ { hidden: true } ],
                           selectionField:  [ { position: 55 } ],
                           identification:  [ { hidden: true } ] }
      @Consumption.filter.defaultValue: ''
      @Consumption.filter.multipleSelections: false
      @Consumption.filter.selectionType: #SINGLE
      @EndUserText.label:'Muhasebeleşti'
      Accounted        : abap_boolean;
      @UI              : {  lineItem:       [ { position: 60 } ],
                            identification: [ { position: 60 } ] }
      @Consumption.filter.hidden : true
      @Semantics.amount.currencyCode: 'CurrencyCode'
      PeriodAmount     : zfi_e_period_amount;
      @UI              : {  lineItem:       [ { hidden: true } ] }
      @Consumption.filter.hidden: true
      @Semantics.currencyCode: true
      CurrencyCode     : waers;
      @UI              : {  lineItem:       [ { position: 70, label: 'Ana Hesap' } ],
                            identification: [ { position: 70, label: 'Ana Hesap' } ] }
      @Consumption.filter.hidden : true
      MainAccount      : zfi_e_saknr;
      @UI              : {  lineItem:       [ { position: 80, label: 'Gider Hesabı' } ],
                            identification: [ { position: 80, label: 'Gider Hesabı' } ] }
      @Consumption.filter.hidden : true
      CostAccount      : zfi_e_saknr;
      @UI              : {  lineItem:       [ { position: 90 } ],
                            identification: [ { position: 90 } ] }
      @Consumption.filter.hidden : true
      DocumentNumber   : zfi_e_document_number;
      @UI              : {  lineItem:       [ { position: 100 } ],
                            identification: [ { position: 100 } ] }
      @Consumption.filter.hidden : true
      DocumentYear     : gjahr;
      @UI              : {  lineItem:       [ { position: 101 },
                            { type: #FOR_ACTION, dataAction: 'accounting', label: 'Muhasebeleştir'},
                            { type: #FOR_ACTION, dataAction: 'reverse', label: 'Ters Kayıt'} ] }
      @UI.hidden       : true
      SimulateComp     : abap_boolean;
      @UI.hidden       : true
      SimulateValid    : abap_boolean;
      @UI              : {  lineItem:       [ { position: 105 } ],
                            identification: [ { position: 105 } ] }
      @EndUserText.label:'Belirteç'
      Identifier       : abap.char( 60 );
}
