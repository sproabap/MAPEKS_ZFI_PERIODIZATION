@EndUserText.label: 'Nesne Türü Bakım Tablosu'
@AccessControl.authorizationCheck: #NOT_ALLOWED
@Metadata.allowExtensions: true
define view entity ZFI_I_OBJTYPEHEADER
  as select from zfi_t_obj_type_h
  association to parent ZFI_I_OBJTYPE_SNG as _ObjectTypeSingleton on $projection.ObjectTypeSingleton = _ObjectTypeSingleton.ObjectTypeSingleton
  composition [1..*] of ZFI_I_OBJTYPEITEM as _ObjectTypeItem
{
  key header_object_type as HeaderObjectType,
  object_type_text as ObjectTypeText,
  number_range_no as NumberRangeNo,
  @Consumption.hidden: true
  1 as ObjectTypeSingleton,
  _ObjectTypeSingleton,
  _ObjectTypeItem
}
