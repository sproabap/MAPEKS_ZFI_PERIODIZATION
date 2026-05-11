@AbapCatalog.sqlViewName: 'ZFI_V_OBJ_TYPE_I'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Nesne Kalem Türü View CDS'
@Metadata.ignorePropagatedAnnotations: true

@ObjectModel: {
dataCategory: #VALUE_HELP,
representativeKey: 'ItemObjectType',
supportedCapabilities: [#VALUE_HELP_PROVIDER]
} 
@UI.presentationVariant: [{ sortOrder: [{ by: 'ItemObjectType', direction: #ASC }] }]

define view ZFI_I_OBJ_TYPE_I as select from zfi_t_obj_type_i
{
    @UI.hidden: true
    key header_object_type as HeaderObjectType,
    key item_object_type as ItemObjectType,
    @EndUserText.label: 'Ana Hesap'
    @Consumption.valueHelpDefinition: [{ entity: { name: 'ZFI_I_GLACCOUNT', element: 'GLAccount'} }]
    main_account as MainAccount,
    @EndUserText.label: 'Gider Hesabı'
    @Consumption.valueHelpDefinition: [{ entity: { name: 'ZFI_I_GLACCOUNT', element: 'GLAccount'} }]
    cost_account as CostAccount,
    @Consumption.valueHelpDefinition: [{ entity: { name: 'I_AccountingDocumentType', element: 'AccountingDocumentType'} }]    
    document_type as DocumentType
}
