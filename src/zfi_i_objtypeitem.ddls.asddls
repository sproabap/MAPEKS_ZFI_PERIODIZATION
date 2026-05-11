@EndUserText.label: 'Nesne Kalem Türü Bakım Tablosu'
@AccessControl.authorizationCheck: #NOT_ALLOWED
@Metadata.allowExtensions: true
define view entity ZFI_I_OBJTYPEITEM
  as select from zfi_t_obj_type_i
  association [1..1] to ZFI_I_OBJTYPE_SNG as _ObjectTypeSingleton on $projection.ObjectTypeSingleton = _ObjectTypeSingleton.ObjectTypeSingleton
  association to parent ZFI_I_OBJTYPEHEADER as _ObjectTypeHeader on $projection.HeaderObjectType = _ObjectTypeHeader.HeaderObjectType
{
  key header_object_type as HeaderObjectType,
  key item_object_type as ItemObjectType,
  main_account as MainAccount,
  cost_account as CostAccount,
  document_type as DocumentType,
  @Consumption.hidden: true
  1 as ObjectTypeSingleton,
  _ObjectTypeSingleton,
  _ObjectTypeHeader
  
}
