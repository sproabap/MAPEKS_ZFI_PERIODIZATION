@AbapCatalog.sqlViewName: 'ZFI_V_OBJ_TYPE_H'
@AbapCatalog.compiler.compareFilter: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Nesne Türü View CDS'
@Metadata.ignorePropagatedAnnotations: true

@ObjectModel: {
dataCategory: #VALUE_HELP,
representativeKey: 'HeaderObjectType',
supportedCapabilities: [#VALUE_HELP_PROVIDER]
} 
@UI.presentationVariant: [{ sortOrder: [{ by: 'HeaderObjectType', direction: #ASC }] }]

define view ZFI_I_OBJ_TYPE_H as select from zfi_t_obj_type_h
{
    @ObjectModel.text.element: ['ObjectTypeText']
    key header_object_type as HeaderObjectType,
    @Semantics.text: true
    object_type_text as ObjectTypeText,
    number_range_no as NumberRangeNo
    
}
