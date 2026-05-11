@AbapCatalog.sqlViewName: 'ZFI_V_GLACCOUNT'
@AbapCatalog.compiler.compareFilter: true
@AbapCatalog.preserveKey: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Hesap Arama Yardımı'
@Metadata.ignorePropagatedAnnotations: true

@ObjectModel: {
dataCategory: #VALUE_HELP,
representativeKey: 'GLAccount',
supportedCapabilities: [#VALUE_HELP_PROVIDER]
} 
@UI.presentationVariant: [{ sortOrder: [{ by: 'GLAccount', direction: #ASC }] }]

define view ZFI_I_GLACCOUNT
as select from I_GLAccount 
{
key CompanyCode,
@ObjectModel.text.association: '_Text'
key GLAccount,
@ObjectModel.text.association: '_ChartOfAccountsText'
ChartOfAccounts,
// Associations
_Text,
_ChartOfAccounts,
_ChartOfAccountsText
};
