@EndUserText.label: 'Nesne Türü Bakımları'
@AccessControl.authorizationCheck: #NOT_ALLOWED
@ObjectModel.semanticKey: [ 'ObjectTypeSingleton' ]
@UI: {
  headerInfo: {
    typeName: 'Giriş',
    title: {
        type: #STANDARD,
        value: 'ObjectTypeSingleton'
    }
  }
}
define root view entity ZFI_I_OBJTYPE_SNG
  as select from I_Language
    left outer join I_CstmBizConfignLastChgd on I_CstmBizConfignLastChgd.ViewEntityName = 'ZFI_I_OBJTYPEHEADER'
  composition [0..*] of ZFI_I_OBJTYPEHEADER as _ObjectTypeHeader
{
  @UI.facet: [ {
    id: 'ZFI_I_OBJTYPEHEADER', 
    purpose: #STANDARD, 
    type: #LINEITEM_REFERENCE, 
    label: 'Nesneler', 
    position: 1 , 
    targetElement: '_ObjectTypeHeader'
  } ]
  @UI.lineItem: [ {
    position: 1 ,
    label: 'Başlangıç'
  } ]
  key 1 as ObjectTypeSingleton,
  _ObjectTypeHeader,
  @UI.hidden: true
  I_CstmBizConfignLastChgd.LastChangedDateTime as LastChangedAtMax
  
}
where I_Language.Language = $session.system_language
