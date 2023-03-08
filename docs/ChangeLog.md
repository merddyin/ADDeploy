# AVADeployAD Change Log

Project Site: [https://github.com/merddyin/ADDeploy](https://github.com/merddyin/ADDeploy)

## Version 0.4.0

- Initial release

## Version 1.4.6

 **Breaking Changes in this version - please read release notes carefully before deploying in an existing implementation**

### General Updates

- New logo
- Fixed folder spelling for splitpipeline plugin
- Updated PSSQLite module from v1.0.3 to v1.1.0
- All cmdlets that used potentially large data sets have been updated to use System.Collections.Generic.List for improved speed

- New Features:
	- Tier and Focus level OUs are now renamable if required
	- Tiered admin account indicators can now be configured in OU_Core table (value and whether to treat as prefix or suffix)
	- Attribute values used to track stamping of Tier, Focus, Scope (SLO), and Object Reference Types can now be configured in OU_Core table (Objects created by tool are auto-stamped)
	- Added support for deploying a Scope (SLO) OU only to specific Tiers or Focus types via Cust_OU_Organization table 
	- New Get cmdlets for quickly retrieving OUs or Task Groups associated with the model
	- A new developer focused cmdlet (remove before distribution) to display variable contents created from the DB at module load
  
- Deprecated/Removed Features
  - All Group Policy related functionality has been stripped for the time being, as this largely requires use of the Microsoft GroupPolicy module; Functionality will be reintroduced at a later time once an API approach is fleshed out
  - The orchestration cmdlet (Publish-ADDESAEStructure) is currently unlikely to function as it has not been updated for the new cmdlets; it has been left in place so that users can see the correct steps order to enable a manual deployment
  - Only a single layer of Scope (SLO) is currently supported for deployment, as opposed to up to three layers previously; This ability will be brought back as soon as I have time to augment the New-ADDOrgUnit and Remove-ADDOrgUnit cmdlets (DB already adjusted) 

### Detailed Component Updates

#### DB Schema

Note: Updated DB schema is not compatible with legacy versions

- Removed unused tables
- Adjustments to AP_Objects for additional extensibility
  - Added and renamed several refids 
  - Added new primery TypeOU values to reduce need of some orgs to create sub-OUs for organization of objects, particularly in larger environments
    - Tasks: Holds all Task Delegation Groups
    - Roles: Holds all Role Groups when using groups instead of Role Accounts
    - Service: Holds all Service Accounts
- Extension of OU_Core table for additional flexibility
- Extension of Cust_OU_Organization table for additional flexibility
- Note: **Breaking change** :Groups OUs now apply a deny ACL for the memberOf for everyone as part of deployment (only TDGs may be nested, and only into Role Groups)

### Postload

- New property collections added or adjusted to support DB schema updates
- New argument completers added for some cmdlets
- **Breaking Change**: Removed load of native MS modules entirely, so GPO placeholder functionality is removed and redirection of users and computers via Install-ADDCoreComponents is broken

### Private Folder Changes

- Renamed several functions to better align with PowerShell standards and stop error in VSCode
	- Prompt-Options is now Show-PromptOptions
	- Run-MemClean is now Invoke-MemClean

- New cmdlets: 
	- ConvertTo-ADDRiskTier for easier conversion of values to associated risk tier
	- Export-ADDModuleData to support write-back of data to DB
	- Find-ADDADObject to abstract search operations (still updating public functions to leverage)
	- Get-CallerPreference for persistence of switch values at runtime (verbose, whatif, etc)
	- New-DynamicParameter to support specific use case for creation of parameter at runtime
	- Remove-ADDADObject to support deprovisioning
	- Update-ADDModuleData to enable live update of DB data and initiate re-import to update variable contents

- Removed cmdlets:
	- Deploy-GPOPlaceHolder has been deprecated temporarily pending non-MS module dependent approach

- Updated cmdlets:
  - New-ADDADObject
    - Add Owner stamp when creating groups
    - Stamp tracking attribute values (Tier, Focus, Scope, and Reference Type)
  - ConvertTo-Elements
    - Reworked processing logic to take better advantage of module updates and enable easier identification of component elements more dynamically
    - Relaxed controls slightly to enable better handling of deviations to address a bug where creation of an OU from another module instance would yield TDGs with blank elements on redeploy

### Public Folder Changes

- Removed cmdlets:
	- Export-ADDGPO: Functionality temporarily deprecated
	- Get-ADDGPOObject: Functionality temporarily deprecated
	- Import-ADDGPO: Functionality temporarily deprecated
	- New-ADDGPObject: Functionality temporarily deprecated
	- New-ADDGPPlaceHolder: Functionality temporarily deprecated
	- New-ADDObjLvlOU: Functionality replaced by New-ADDOrgUnit
	- New-ADDOrgLvlOU: Functionality replaced by New-ADDOrgUnit
	- New-ADDTopLvlOU: Functionality replaced by New-ADDOrgUnit
	- Remove-ADDObjLvlOU: Functionality replaced by Remove-ADDOrgUnit
	- Remove-ADDOrgLvlOU: Functionality replaced by Remove-ADDOrgUnit
	- Remove-ADDTaskGroup: Functionality temporarily deprecated
	- Revoke-ADDTDGRights: Functionality deprecated
	
- New cmdlets:
	- Get-ADDOrgUnit: Gets framework related OUs at various levels for use in other cmdlets
	- Get-ADDTaskGroup: Gets all tasks groups per a defined filter for use in other cmdlets
	- New-ADDOrgUnit: Consolidates OU creation for all levels into a single cmdlet with support for ad-hoc deployment
		- Note: Only a single level of SLO/Organizational OUs is currently supported, though enhancement to add this back is in the works
	- Publish-ADDDBMemData: Developer helper function to dump DB values used at runtime
	- Remove-ADDOrgUnit: Consolidates OU removal for all levels into a single cmdlet

- Updated cmdlets:
  - Grant-ADDTDGRights
    - Minor flow updates for efficiency
    - **Known Issues** 
      - Due to MS security updates in Dec 2022, current ACLs applied to enable creation and deletion of objects is broken
      - Bug: Currently unable to delete computer objects when deployed as IaaS on Azure, as a Hyper-V VM, or for some cluster objects due to lack of an ACL permitting removal of all child objects
  - Install-ADDCoreComponents
    - Updates to flow to accommodate other structural module changes (can now be run after all other deployment steps, whereas prior behavior required early execution of this cmdlet)
    - Updated process to leverage OU_Core table instead of OU_PropGroups for core TDG creation to resolve bug where multiple instances of each control group were created
    - **Known Issues**
      - Currently the redirection of the default location for user and computer objects is broken as this depended upon the MS Active Directory module, so cmdlet should be run with -noredir switch to avoid errors
  - New-ADDTaskGroup
    - Removed the 'CreateLevel' parameter, along with all associated code as level is always determined by the OU that is fed into the cmdlet
    - Added the 'Owner' parameter as a required value so that TDGs are all appropriately stamped with the name of the platform owner for auditing purposes
    - Adjusted code to take better advantage of splatting for shared values when calling other cmdlets
    - Bug fix to address an issue where the Tier was being incorrectly interpreted by the shell as an ASCII character, resulting in corrupted name values being set in AD

