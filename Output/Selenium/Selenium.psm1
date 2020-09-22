using namespace System.Collections.Generic


$Script:SeKeys = [OpenQA.Selenium.Keys] | Get-Member -MemberType Property -Static |
    Select-Object -Property Name, @{N = "ObjectString"; E = { "[OpenQA.Selenium.Keys]::$($_.Name)" } }

[Dictionary[object, Stack[string]]] $Script:SeLocationMap = [Dictionary[object, Stack[string]]]::new()

#region Set path to assemblies on Linux and MacOS and Grant Execution permissions on them
if ($IsLinux) {
    $AssembliesPath = "$PSScriptRoot/assemblies/linux"
}
elseif ($IsMacOS) {
    $AssembliesPath = "$PSScriptRoot/assemblies/macos"
}

# Grant Execution permission to assemblies on Linux and MacOS
if ($AssembliesPath) {
    # Check if powershell is NOT running as root
    Get-Item -Path "$AssembliesPath/chromedriver", "$AssembliesPath/geckodriver" | ForEach-Object {
        if ($IsLinux) { $FileMod = stat -c "%a" $_.FullName }
        elseif ($IsMacOS) { $FileMod = /usr/bin/stat -f "%A" $_.FullName }
        Write-Verbose "$($_.FullName) $Filemod"
        if ($FileMod[2] -ne '5' -and $FileMod[2] -ne '7') {
            Write-Host "Granting $($AssemblieFile.fullname) Execution Permissions ..."
            chmod +x $_.fullname
        }
    }
}

$Script:SeDriversAdditionalBrowserSwitches = @{
    Chrome           = @('DisableAutomationExtension', 'EnablePDFViewer')
    Edge             = @()
    Firefox          = @('SuppressLogging')
    InternetExplorer = @('IgnoreProtectedModeSettings')
    MsEdge           = @()
}

# List of suggested command line arguments for each browser
$Script:SeDriversBrowserArguments = @{
    Chrome           = @("--user-agent=Android")
    Edge             = @()
    Firefox          = @()
    InternetExplorer = @()
    MsEdge           = @()
}

$Script:SeDrivers = [System.Collections.Generic.List[PSObject]]::new()
$Script:SeDriversCurrent = $null


$AdditionalOptionsSwitchesCompletion = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    if ($fakeBoundParameters.ContainsKey('Browser')) {
        $Browser = $fakeBoundParameters.Item('Browser')
        
        $Output = $Script:SeDriversAdditionalBrowserSwitches."$Browser"
        $Output | % { [System.Management.Automation.CompletionResult]::new($_) }
        
        
    }
}


$SeDriversBrowserArgumentsCompletion = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    if ($fakeBoundParameters.ContainsKey('Browser')) {
        $Browser = $fakeBoundParameters.Item('Browser')
        $Output = $Script:SeDriversBrowserArguments."$Browser" | Where { $_ -like "*$wordToComplete*" }
        $ptext = [System.Management.Automation.CompletionResultType]::ParameterValue
        $Output | % { [System.Management.Automation.CompletionResult]::new("'$_'", $_, $ptext, $_) }
    }
}

Register-ArgumentCompleter -CommandName Start-SeDriver, New-SeDriverOptions -ParameterName Switches -ScriptBlock $AdditionalOptionsSwitchesCompletion 
Register-ArgumentCompleter -CommandName Start-SeDriver, New-SeDriverOptions -ParameterName Arguments -ScriptBlock $SeDriversBrowserArgumentsCompletion 
function Add-SeDriverOptionsArgument {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true, Position = 0)]
        [OpenQA.Selenium.DriverOptions]$InputObject,
        [ArgumentCompleter( { [Enum]::GetNames([SeBrowsers]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBrowsers]) })]
        [Parameter(Position = 0)]
        $Browser,
        [Parameter(Mandatory = $true, Position = 1)]
        [String]$Name,
        [Parameter(Mandatory = $true, Position = 1)]
        [String]$Value
    )
    
    
    Write-Host $InputObject.SeBrowser -ForegroundColor Cyan
    Write-Host  ($null -eq $Browser)
    Write-Host '---'
}



function Clear-SeAlert {
    param (
        [parameter(ParameterSetName = 'Alert', Position = 0, ValueFromPipeline = $true)]
        $Alert,
        [ValidateIsWebDriverAttribute()]
        $Driver,
        [ValidateSet('Accept', 'Dismiss')]
        $Action = 'Dismiss',
        [switch]$PassThru
    )
    if ($Driver) {
        try { 
            $WebDriverWait = [OpenQA.Selenium.Support.UI.WebDriverWait]::new($Driver, (New-TimeSpan -Seconds 10))
            $Condition = [OpenQA.Selenium.Support.UI.ExpectedConditions]::AlertIsPresent()
            $WebDriverWait.Until($Condition)
            $Alert = $Driver.SwitchTo().alert() 
        }
        catch { Write-Warning 'No alert was displayed'; return }
    }
    if ($Alert) { $alert.$action() }
    if ($PassThru) { $Alert }
}

function Clear-SeSelectValue {
    [Cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [OpenQA.Selenium.IWebElement]$Element 
    )
    [SeleniumSelection.Option]::DeselectAll($Element)        
  
}

function Get-SeCookie {
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [ValidateIsWebDriverAttribute()]
        $Driver 
    )
    Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    $Driver.Manage().Cookies.AllCookies.GetEnumerator()
}
function Get-SeDriver {
    [cmdletbinding(DefaultParameterSetName = 'Current')]
    param(
        [parameter(ParameterSetName = 'Current', Mandatory = $false)]
        [Switch]$Current,
        [parameter(Position = 0, ParameterSetName = 'ByName', Mandatory = $false)]
        [String]$Name,
        [parameter(ParameterSetName = 'ByBrowser', Mandatory = $false)]
        [ArgumentCompleter( { [Enum]::GetNames([SeBrowsers]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBrowsers]) })]
        $Browser
        
        
    
    )
    

    if ($Script:SeDrivers.count -eq 0) { return $null }
    if ($Current) { return $Script:SeDriversCurrent }


    if ($PSBoundParameters.ContainsKey('Browser')) { 
        return $Script:SeDrivers.Where( { $Browser -like "$($_.SeBrowser)*" } )
    }
    
    if ($PSBoundParameters.ContainsKey('Name')) { 
        return $Script:SeDrivers.Where( { $_.SeFriendlyName -eq $Name }, 'first' )
    }

    return $Script:SeDrivers

}

function Get-SeElement {
    [Cmdletbinding(DefaultParameterSetName = 'Default')]
    param(
        #Specifies whether the selction text is to select by name, ID, Xpath etc
        [ArgumentCompleter( { [Enum]::GetNames([SeBySelector]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBySelector]) })]
        [SeBySelector]$By = [SeBySelector]::XPath,
        [Parameter(Position = 1, Mandatory = $true)]
        [string]$Value,
        #Specifies a time out
        [Parameter(Position = 2, ParameterSetName = 'Default')]
        [Int]$Timeout = 0,
        #The driver or Element where the search should be performed.
        [Parameter(Position = 3, ValueFromPipeline = $true, ParameterSetName = 'Default')]
        [OpenQA.Selenium.IWebDriver]
        $Driver,
        [Parameter(Position = 3, ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = 'ByElement')]
        [OpenQA.Selenium.IWebElement]
        $Element,
        [Switch]$All,
        [ValidateNotNullOrEmpty()]
        [String[]]$Attributes
    )
    Begin {
        Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
        $ShowAll = $PSBoundParameters.ContainsKey('All') -and $PSBoundParameters.Item('All') -eq $true
        
        Filter DisplayedFilter([Switch]$All) {
            if ($All) { $_ } else { if ($_.Displayed) { $_ } } 
        }
        $Output = $null
    }
    process {
      
        
        
        switch ($PSCmdlet.ParameterSetName) {
            'Default' { 
                if ($Timeout) {
                    $TargetElement = [OpenQA.Selenium.By]::$By($Value)
                    $WebDriverWait = [OpenQA.Selenium.Support.UI.WebDriverWait]::new($Driver, (New-TimeSpan -Seconds $Timeout))
                    $Condition = [OpenQA.Selenium.Support.UI.ExpectedConditions]::ElementExists($TargetElement)
                    $Output = $WebDriverWait.Until($Condition) | DisplayedFilter -All:$ShowAll
                }
                else {
                    $Output = $Driver.FindElements([OpenQA.Selenium.By]::$By($Value)) | DisplayedFilter -All:$ShowAll
                }
            }
            'ByElement' {
                Write-Warning "Timeout does not apply when searching an Element" 
                $Output = $Element.FindElements([OpenQA.Selenium.By]::$By($Value)) | DisplayedFilter -All:$ShowAll
            }
        }
        
 

        if ($PSBoundParameters.ContainsKey('Attributes')) {
            $GetAllAttributes = $Attributes.Count -eq 1 -and $Attributes[0] -eq '*'
            
            if ($GetAllAttributes) {
                Foreach ($Item in $Output) {
                    $AllAttributes = $Driver.ExecuteScript('var items = {}; for (index = 0; index < arguments[0].attributes.length; ++index) { items[arguments[0].attributes[index].name] = arguments[0].attributes[index].value }; return items;', $Item)
                    $AttArray = [System.Collections.Generic.Dictionary[String, String]]::new()

                    Foreach ($AttKey in $AllAttributes.Keys) {
                        $AttArray.Add($AttKey, $AllAttributes[$AttKey])
                    }

                    Add-Member -InputObject $Item -Name 'Attributes' -Value $AttArray -MemberType NoteProperty
                }
            }
            else {
                foreach ($Item in $Output) {
                    $AttArray = [System.Collections.Generic.Dictionary[String, String]]::new()
                 
                    foreach ($att in $Attributes) {
                        $Value = $Item.GetAttribute($att)
                        if ($Value -ne "") {
                            $AttArray.Add($att, $Item.GetAttribute($att))
                        }
                
                    }
                    Add-Member -InputObject $Item -Name 'Attributes' -Value $AttArray -MemberType NoteProperty
                }

                  
                    


                
            }
              
        }


        return $Output
    }
}


function Get-SeElementAttribute {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [OpenQA.Selenium.IWebElement]$Element,
        [Parameter(Mandatory = $true)]
        [string]$Attribute
    )
    process {
        $Element.GetAttribute($Attribute)
    }
}
function Get-SeElementCssValue {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [OpenQA.Selenium.IWebElement]$Element,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Process {
        $Element.GetCssValue($Name)
    }
}
function Get-SeHtml {
    param(
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [OpenQA.Selenium.IWebElement]$Element,
        [switch]$Inner
        
    )
    if ($Inner) { return $Element.GetAttribute('innerHTML') }
    return $Element.GetAttribute('outerHTML')
}

function Get-SeKeys {
    [OpenQA.Selenium.Keys] | 
        Get-Member -MemberType Property -Static | 
            Select-Object -Property Name, @{N = "ObjectString"; E = { "[OpenQA.Selenium.Keys]::$($_.Name)" } }
}
function Get-SeSelectValue {
    [cmdletbinding(DefaultParameterSetName = 'default')]
    param (
        [Parameter( ValueFromPipeline = $true, Mandatory = $true, Position = 1)]
        [OpenQA.Selenium.IWebElement]$Element,
        [ref]$IsMultiSelect,
        [Switch]$All
    )
    try {
        $IsMultiSelectResult = [SeleniumSelection.Option]::IsMultiSelect($Element)
        
        if ($PSBoundParameters.ContainsKey('IsMultiSelect')) { $IsMultiSelect.Value = $IsMultiSelectResult }

        if ($All) {
            return  ([SeleniumSelection.Option]::GetOptions($Element)).Text
        }
        elseif ($IsMultiSelectResult) {
            return [SeleniumSelection.Option]::GetAllSelectedOptions($Element).text
        }
        else {
            return [SeleniumSelection.Option]::GetSelectedOption($Element).text
        }

        
               

    }
    catch {
        throw "An error occured checking the selection box, the message was:`r`n $($_.exception.message)"
    }
}
function Get-SeUrl {
    <#
    .SYNOPSIS
    Retrieves the current URL of a target webdriver instance.

    .DESCRIPTION
    Retrieves the current URL of a target webdriver instance, or the currently
    stored internal location stack.

    .EXAMPLE
    Get-SeUrl

    Retrieves the current URL of the default webdriver instance.

    .NOTES
    When using -Stack, the retrieved stack will not contain any of the driver's
    history (Back/Forward) data. It only handles locations added with
    Push-SeUrl.

    To utilise a driver's Back/Forward functionality, instead use Set-SeUrl.
    #>
    [CmdletBinding()]
    param(
        # Optionally retrieve the stored URL stack for the target or default
        # webdriver instance.
        [Parameter()]
        [switch]
        $Stack,

        # The webdriver instance for which to retrieve the current URL or
        # internal URL stack.
        [Parameter(ValueFromPipeline = $true)]
        [ValidateIsWebDriverAttribute()]
        $Driver
    )
    Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    
    if ($Stack) {
        if ($Script:SeLocationMap[$Driver].Count -gt 0) {
            $Script:SeLocationMap[$Driver].ToArray()
        }
    }
    else {
        $Driver.Url
    }
}
function Get-SeWindow {
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [OpenQA.Selenium.IWebDriver]
        $Driver 
    )
    begin {
        Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    }
    process {
        $Driver.WindowHandles
    }
}
function New-SeDriverOptions {
    [cmdletbinding()]
    [OutputType(
        [OpenQA.Selenium.Chrome.ChromeOptions],
        [OpenQA.Selenium.Edge.EdgeOptions],
        [OpenQA.Selenium.Firefox.FirefoxOptions],
        [OpenQA.Selenium.IE.InternetExplorerOptions]
    )]
    param(
        [ArgumentCompleter( { [Enum]::GetNames([SeBrowsers]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBrowsers]) })]
        [Parameter(ParameterSetName = 'Default')]
        $Browser,
        [ValidateURIAttribute()]
        [Parameter(Position = 1)]
        [string]$StartURL,
        [ArgumentCompleter( { [Enum]::GetNames([SeWindowState]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeWindowState]) })]
        $State,
        [System.IO.FileInfo]$DefaultDownloadPath,
        [switch]$PrivateBrowsing,
        [int]$ImplicitWait = 10,
        [System.Drawing.Size][SizeTransformAttribute()]$Size,
        [System.Drawing.Point][PointTransformAttribute()]$Position,
        $WebDriverPath,
        $BinaryPath,
        [String[]]$Switches,
        [String[]]$Arguments,
        $ProfilePath,
        [OpenQA.Selenium.LogLevel]$LogLevel
    )
    #  [Enum]::GetNames([sebrowsers])
    $output = $null
    switch ($Browser) {
        Chrome { $Output = [OpenQA.Selenium.Chrome.ChromeOptions]::new() }
        Edge { $Output = [OpenQA.Selenium.Edge.EdgeOptions]::new() }
        Firefox { $Output = [OpenQA.Selenium.Firefox.FirefoxOptions]::new() }
        InternetExplorer { $Output = [OpenQA.Selenium.IE.InternetExplorerOptions]::new() }
        MSEdge { $Output = [OpenQA.Selenium.Edge.EdgeOptions]::new() }
    }

    #Add members to be treated by Internal Start cmdlet since Start-SeDriver won't allow their use with Options parameter set.
    Add-Member -InputObject $output -MemberType NoteProperty -Name 'SeParams' -Value $PSBoundParameters
    

    return $output
}
function New-SeDriverService {
    [cmdletbinding()]
    [OutputType(
        [OpenQA.Selenium.Chrome.ChromeDriverService],
        [OpenQA.Selenium.Firefox.FirefoxDriverService],
        [OpenQA.Selenium.IE.InternetExplorerDriverService],
        [OpenQA.Selenium.Edge.EdgeDriverService]
    )]
    param(
        [ArgumentCompleter( { [Enum]::GetNames([SeBrowsers]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBrowsers]) })]
        [Parameter(ParameterSetName = 'Default')]
        $Browser,
        $WebDriverPath
    )

    #$AssembliesPath defined in init.ps1
    $service = $null
    $ServicePath = $null
    
    if ($WebDriverPath) { $ServicePath = $WebDriverPath } elseif ($AssembliesPath) { $ServicePath = $AssembliesPath }
    
    switch ($Browser) {
        
        Chrome { 
            if ($ServicePath) { $service = [OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService($ServicePath) }
            else { $service = [OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService() }
        }
        Edge { 
            $service = [OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService($WebDriverPath, 'msedgedriver.exe')
        }
        Firefox { 
            if ($ServicePath) { $service = [OpenQA.Selenium.Firefox.FirefoxDriverService]::CreateDefaultService($ServicePath) }
            else { $service = [OpenQA.Selenium.Firefox.FirefoxDriverService]::CreateDefaultService() }
            $service.Host = '::1'
        }
        InternetExplorer { 
            if ($WebDriverPath) { $Service = [OpenQA.Selenium.IE.InternetExplorerDriverService]::CreateDefaultService($WebDriverPath) }
            else { $Service = [OpenQA.Selenium.IE.InternetExplorerDriverService]::CreateDefaultService() }
            
        }
        MSEdge { 
            $service = [OpenQA.Selenium.Edge.EdgeDriverService]::CreateDefaultService()
        }
    }

    #Set to $true by default; removing it will cause problems in jobs and create a second source of Verbose in the console.
    $Service.HideCommandPromptWindow = $true 

    return $service
}

function New-SeScreenshot {
    [cmdletbinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [ValidateIsWebDriverAttribute()]
        $Driver,
        [Parameter(ParameterSetName = 'Base64', Mandatory = $true)]
        [Switch]$AsBase64EncodedString
    )
    Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    $Screenshot = [OpenQA.Selenium.Support.Extensions.WebDriverExtensions]::TakeScreenshot($Driver)

    if ($AsBase64EncodedString) {
        return $Screenshot.AsBase64EncodedString 
    }

    return $Screenshot
}
function Pop-SeUrl {
    <#
    .SYNOPSIS
    Navigate back to the most recently pushed URL in the location stack.

    .DESCRIPTION
    Retrieves the most recently pushed URL from the location stack and navigates
    to that URL with the specified or default driver.

    .EXAMPLE
    Pop-SeUrl

    Retrieves the most recently pushed URL and navigates back to that URL.

    .NOTES
    A separate internal location stack is maintained for each driver instance
    by the module. This stack is completely separate from the driver's internal
    Back/Forward history logic.

    To utilise a driver's Back/Forward functionality, instead use Set-SeUrl.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [ValidateIsWebDriverAttribute()]
        $Driver 
    )
    begin {
        Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    }
    process {
        if ($Script:SeLocationMap[$Driver].Count -gt 0) {
            Set-SeUrl -Url $Script:SeLocationMap[$Driver].Pop() -Driver $Driver
        }
    }
}
function Push-SeUrl {
    <#
    .SYNOPSIS
    Stores the current URL in the driver's location stack and optionally
    navigate to a new URL.

    .DESCRIPTION
    The current driver URL is added to the stack, and if a URL is provided, the
    driver navigates to the new URL.

    .EXAMPLE
    Push-SeUrl

    The current driver URL is added to the location stack.

    .EXAMPLE
    Push-SeUrl 'https://google.com/'

    The current driver URL is added to the location stack, and the driver then
    navigates to the provided target URL.

    .NOTES
    A separate internal location stack is maintained for each driver instance
    by the module. This stack is completely separate from the driver's internal
    Back/Forward history logic.

    To utilise a driver's Back/Forward functionality, instead use Set-SeUrl.
    #>
    [CmdletBinding()]
    param(
        # The new URL to navigate to after storing the current location.
        [Parameter(Position = 0, ParameterSetName = 'url')]
        [ValidateURIAttribute()]
        [string]
        $Url,

        # The webdriver instance that owns the url stack, and will navigate to
        # a provided new url (if any).
        [Parameter(ValueFromPipeline = $true)]
        [ValidateIsWebDriverAttribute()]
        $Driver 
    )
    Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    if (-not $Script:SeLocationMap.ContainsKey($Driver)) {
        $script:SeLocationMap[$Driver] = [System.Collections.Generic.Stack[string]]@()
    }

    # Push the current location to the stack
    $script:SeLocationMap[$Driver].Push($Driver.Url)

    if ($Url) {
        # Change the driver current URL to provided URL
        Set-SeUrl -Url $Url -Driver $Driver
    }
}
function Remove-SeCookie {
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [OpenQA.Selenium.IWebDriver]
        $Driver,
 
        [Parameter(Mandatory = $true, ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(Mandatory = $true, ParameterSetName = 'NamedCookie')] 
        [string]$Name
    )
    Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    if ($All) {
        $Driver.Manage().Cookies.DeleteAllCookies()
    }
    else {
        $Driver.Manage().Cookies.DeleteCookieNamed($Name)
    }
}
function Save-SeScreenshot {
    param(
        [ValidateIsWebDriverAttribute()]
        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'Default')]
        $Driver ,
        [Parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = 'Screenshot')]
        [OpenQA.Selenium.Screenshot]$Screenshot,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter()]
        [OpenQA.Selenium.ScreenshotImageFormat]$ImageFormat = [OpenQA.Selenium.ScreenshotImageFormat]::Png)

    begin {
        if ($PSCmdlet.ParameterSetName -eq 'Default') {
            Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Default') {

            try {
                $Screenshot = New-SeScreenshot -Driver $Driver
            }
            catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
            
        }
        $Screenshot.SaveAsFile($Path, $ImageFormat)
    }
}
function Select-SeDriver {
    [cmdletbinding(DefaultParameterSetName = 'ByName')]
    param(
        [parameter(Position = 0, ParameterSetName = 'ByDriver', Mandatory = $True)]
        [OpenQA.Selenium.IWebDriver]$Driver,
        [parameter(Position = 0, ParameterSetName = 'ByName', Mandatory = $True)]
        [String]$Name
    )

    # Remove Selected visual indicator
    if ($null -ne $Script:SeDriversCurrent) { 
        $Script:SeDriversCurrent.SeBrowser = $Script:SeDriversCurrent.SeBrowser -replace ' \*$', ''
    }

    switch ($PSCmdlet.ParameterSetName) {
        'ByDriver' { $Script:SeDriversCurrent = $Driver }
        'ByName' {
            $Driver = Get-SeDriver -Name $Name 
            if ($null -eq $Driver) {
                $PSCmdlet.ThrowTerminatingError("Driver with Name: $Name not found ")
            }
            else {
                $Script:SeDriversCurrent = $Driver
            }
        }
    }

    $Driver.SeBrowser = "$($Driver.SeBrowser) *"

    return $Driver
}

function Send-SeClick {
    param(
        [Parameter( ValueFromPipeline = $true, Mandatory = $true, Position = 0)]
        [OpenQA.Selenium.IWebElement]$Element,
        [Switch]$JavaScript,
        $SleepSeconds = 0 ,
        $Driver ,
        [switch]$PassThru
    )
    begin {
        Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    }
    Process {
        if ($JavaScriptClick) {
            try {
                $Driver.ExecuteScript("arguments[0].click()", $Element)
            }
            catch {
                $PSCmdlet.ThrowTerminatingError($_)
            }
        }
        else {
            $Element.Click()
        }

        if ($SleepSeconds) { Start-Sleep -Seconds $SleepSeconds }
        if ($PassThru) { $Element }
    }
}
function Send-SeKeys {
    param(
        [Parameter( Position = 0, ValueFromPipeline = $true, Mandatory = $true)]
        [ValidateNotNull()]
        [OpenQA.Selenium.IWebElement]$Element ,
        [Parameter(Mandatory = $true, Position = 1)]
        [AllowEmptyString()]
        [string]$Keys,
        [switch]$ClearFirst,
        $SleepSeconds = 0 ,
        [switch]$Submit,
        [switch]$PassThru
    )
    begin {
        foreach ($Key in $Script:SeKeys.Name) {
            $Keys = $Keys -replace "{{$Key}}", [OpenQA.Selenium.Keys]::$Key
        }
    }
    process {
        if ($ClearFirst) { $Element.Clear() }

        $Element.SendKeys($Keys)

        if ($Submit) { $Element.Submit() }
        if ($SleepSeconds) { Start-Sleep -Seconds $SleepSeconds }
        if ($PassThru) { $Element }
    }
}
function SeShouldHave {
    [cmdletbinding(DefaultParameterSetName = 'DefaultPS')]
    param(
        [Parameter(ParameterSetName = 'DefaultPS', Mandatory = $true , Position = 0, ValueFromPipeline = $true)]
        [Parameter(ParameterSetName = 'Element' , Mandatory = $true , Position = 0, ValueFromPipeline = $true)]
        [string[]]$Selection,

        [Parameter(ParameterSetName = 'DefaultPS', Mandatory = $false)]
        [Parameter(ParameterSetName = 'Element' , Mandatory = $false)]
        [ArgumentCompleter( { [Enum]::GetNames([SeBySelector]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBySelector]) })]
        [string]$By = [SeBySelector]::XPath,

        [Parameter(ParameterSetName = 'Element' , Mandatory = $true , Position = 1)]
        [string]$With,

        [Parameter(ParameterSetName = 'Alert' , Mandatory = $true)]
        [switch]$Alert,
        [Parameter(ParameterSetName = 'NoAlert' , Mandatory = $true)]
        [switch]$NoAlert,
        [Parameter(ParameterSetName = 'Title' , Mandatory = $true)]
        [switch]$Title,
        [Parameter(ParameterSetName = 'URL' , Mandatory = $true)]
        [switch]$URL,
        [Parameter(ParameterSetName = 'Element' , Mandatory = $false, Position = 3)]
        [Parameter(ParameterSetName = 'Alert' , Mandatory = $false, Position = 3)]
        [Parameter(ParameterSetName = 'Title' , Mandatory = $false, Position = 3)]
        [Parameter(ParameterSetName = 'URL' , Mandatory = $false, Position = 3)]
        [ValidateSet('like', 'notlike', 'match', 'notmatch', 'contains', 'eq', 'ne', 'gt', 'lt')]
        [OperatorTransformAttribute()]
        [String]$Operator = 'like',

        [Parameter(ParameterSetName = 'Element' , Mandatory = $false, Position = 4)]
        [Parameter(ParameterSetName = 'Alert' , Mandatory = $false, Position = 4)]
        [Parameter(ParameterSetName = 'Title' , Mandatory = $true , Position = 4)]
        [Parameter(ParameterSetName = 'URL' , Mandatory = $true , Position = 4)]
        [Alias('contains', 'like', 'notlike', 'match', 'notmatch', 'eq', 'ne', 'gt', 'lt')]
        [AllowEmptyString()]
        $Value,

        [Parameter(ParameterSetName = 'DefaultPS')]
        [Parameter(ParameterSetName = 'Element')]
        [Parameter(ParameterSetName = 'Alert')]
        [switch]$PassThru,

        [Int]$Timeout = 0
    )
    begin {
        $endTime = [datetime]::now.AddSeconds($Timeout)
        $lineText = $MyInvocation.Line.TrimEnd("$([System.Environment]::NewLine)")
        $lineNo = $MyInvocation.ScriptLineNumber
        $file = $MyInvocation.ScriptName
        Function expandErr {
            param ($message)
            [Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($message),
                'PesterAssertionFailed',
                [Management.Automation.ErrorCategory]::InvalidResult,
                @{
                    Message  = $message
                    File     = $file
                    Line     = $lineNo
                    Linetext = $lineText
                }
            )
        }
        function applyTest {
            param(
                $Testitems,
                $Operator,
                $Value
            )
            Switch ($Operator) {
                'Contains' { return ($testitems -contains $Value) }
                'eq' { return ($TestItems -eq $Value) }
                'ne' { return ($TestItems -ne $Value) }
                'like' { return ($TestItems -like $Value) }
                'notlike' { return ($TestItems -notlike $Value) }
                'match' { return ($TestItems -match $Value) }
                'notmatch' { return ($TestItems -notmatch $Value) }
                'gt' { return ($TestItems -gt $Value) }
                'le' { return ($TestItems -lt $Value) }
            }
        }

        #if operator was not passed, allow it to be taken from an alias for the -value
        if (-not $PSBoundParameters.ContainsKey('operator') -and $lineText -match ' -(eq|ne|contains|match|notmatch|like|notlike|gt|lt) ') {
            $Operator = $matches[1]
        }
        $Success = $false
        $foundElements = [System.Collections.Generic.List[PSObject]]::new()
    }
    process {
        #If we have been asked to check URL or title get them from the driver. Otherwise call Get-SEElement.
        if ($URL) {
            do {
                $Success = applyTest -testitems $Script:SeDriversCurrent.Url -operator $Operator -value $Value
                Start-Sleep -Milliseconds 500
            }
            until ($Success -or [datetime]::now -gt $endTime)
            if (-not $Success) {
                throw (expandErr "PageURL was $($Script:SeDriversCurrent.Url). The comparison '-$operator $value' failed.")
            }
        }
        elseif ($Title) {
            do {
                $Success = applyTest -testitems $Script:SeDriversCurrent.Title -operator $Operator -value $Value
                Start-Sleep -Milliseconds 500
            }
            until ($Success -or [datetime]::now -gt $endTime)
            if (-not $Success) {
                throw (expandErr "Page title was $($Script:SeDriversCurrent.Title). The comparison '-$operator $value' failed.")
            }
        }
        elseif ($Alert -or $NoAlert) {
            do {
                try {
                    $a = $Script:SeDriversCurrent.SwitchTo().alert()
                    $Success = $true
                }
                catch {
                    Start-Sleep -Milliseconds 500
                }
                finally {
                    if ($NoAlert -and $a) { throw (expandErr "Expected no alert but an alert of '$($a.Text)' was displayed") }
                }
            }
            until ($Success -or [datetime]::now -gt $endTime)

            if ($Alert -and -not $Success) {
                throw (expandErr "Expected an alert but but none was displayed")
            }
            elseif ($value -and -not (applyTest -testitems $a.text -operator $Operator -value $value)) {
                throw (expandErr "Alert text was $($a.text). The comparison '-$operator $value' failed.")
            }
            elseif ($PassThru) { return $a }
        }
        else {
            foreach ($s in $Selection) {
                $GSEParams = @{By = $By; Value = $s }
                if ($Timeout) { $GSEParams['Timeout'] = $Timeout }
                try { $e = Get-SeElement @GSEParams -All }
                catch { throw (expandErr $_.Exception.Message) }

                #throw if we didn't get the element; if were only asked to check it was there, return gracefully
                if (-not $e) { throw (expandErr "Didn't find '$s' by $by") }
                else {
                    Write-Verbose "Matched element(s) for $s"
                    $foundElements.add($e)
                }
            }
        }
    }
    end {
        if ($PSCmdlet.ParameterSetName -eq "DefaultPS" -and $PassThru) { return $e }
        elseif ($PSCmdlet.ParameterSetName -eq "DefaultPS") { return }
        else {
            foreach ($e in $foundElements) {
                switch ($with) {
                    'Text' { $testItem = $e.Text }
                    'Displayed' { $testItem = $e.Displayed }
                    'Enabled' { $testItem = $e.Enabled }
                    'TagName' { $testItem = $e.TagName }
                    'X' { $testItem = $e.Location.X }
                    'Y' { $testItem = $e.Location.Y }
                    'Width' { $testItem = $e.Size.Width }
                    'Height' { $testItem = $e.Size.Height }
                    'Choice' { $testItem = (Get-SeSelectValue -Element $e -All) }
                    default { $testItem = $e.GetAttribute($with) }
                }
                if (-not $testItem -and ($Value -ne '' -and $foundElements.count -eq 1)) {
                    throw (expandErr "Didn't find '$with' on element")
                }
                if (applyTest -testitems $testItem -operator $Operator -value $Value) {
                    $Success = $true
                    if ($PassThru) { $e }
                }
            }
            if (-not $Success) {
                if ($foundElements.count -gt 1) {
                    throw (expandErr "$Selection match $($foundElements.Count) elements, none has a value for $with which passed the comparison '-$operator $value'.")
                }
                else {
                    throw (expandErr "$with had a value of $testitem which did not pass the the comparison '-$operator $value'.")
                }
            }
        }
    }
}
function Set-SeCookie {
    [cmdletbinding()]
    param(
        [string]$Name,
        [string]$Value,
        [string]$Path,
        [string]$Domain,
        $ExpiryDate,

        [Parameter(ValueFromPipeline = $true)]
        [ValidateIsWebDriverAttribute()]
        $Driver 
    )
    begin {
        Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
        if ($null -ne $ExpiryDate -and $ExpiryDate.GetType().Name -ne 'DateTime') {
            throw '$ExpiryDate can only be $null or TypeName: System.DateTime'
        }
    }

    process {
        if ($Name -and $Value -and (!$Path -and !$Domain -and !$ExpiryDate)) {
            $cookie = [OpenQA.Selenium.Cookie]::new($Name, $Value)
        }
        Elseif ($Name -and $Value -and $Path -and (!$Domain -and !$ExpiryDate)) {
            $cookie = [OpenQA.Selenium.Cookie]::new($Name, $Value, $Path)
        }
        Elseif ($Name -and $Value -and $Path -and $ExpiryDate -and !$Domain) {
            $cookie = [OpenQA.Selenium.Cookie]::new($Name, $Value, $Path, $ExpiryDate)
        }
        Elseif ($Name -and $Value -and $Path -and $Domain -and (!$ExpiryDate -or $ExpiryDate)) {
            if ($Driver.Url -match $Domain) {
                $cookie = [OpenQA.Selenium.Cookie]::new($Name, $Value, $Domain, $Path, $ExpiryDate)
            }
            else {
                Throw 'In order to set the cookie the browser needs to be on the cookie domain URL'
            }
        }
        else {
            Throw "Incorrect Cookie Layout:
            Cookie(String, String)
            Initializes a new instance of the Cookie class with a specific name and value.
            Cookie(String, String, String)
            Initializes a new instance of the Cookie class with a specific name, value, and path.
            Cookie(String, String, String, Nullable<DateTime>)
            Initializes a new instance of the Cookie class with a specific name, value, path and expiration date.
            Cookie(String, String, String, String, Nullable<DateTime>)
            Initializes a new instance of the Cookie class with a specific name, value, domain, path and expiration date."
        }

        $Driver.Manage().Cookies.AddCookie($cookie)
    }
}
function Set-SeSelectValue {
    param (
        [ArgumentCompleter( { [Enum]::GetNames([SeBySelect]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBySelect]) })]
        [SeBySelect]$By = [SeBySelect]::Text,
        [Parameter( ValueFromPipeline = $true, Position = 1, Mandatory = $true)]
        [OpenQA.Selenium.IWebElement]$Element,
        [Object]$value
    )
    try {
        $IsMultiSelect = [SeleniumSelection.Option]::IsMultiSelect($Element)

        if (-not $IsMultiSelect -and $Value.Count -gt 1) {
            Write-Error 'This select control do not accept multiple values'
            return $null
        }
  
        #byindex can be 0, but ByText and ByValue can't be empty strings
        switch ($By) {
            { $_ -eq [SeBySelect]::Text } {
                $HaveWildcards = $null -ne (Get-WildcardsIndices -Value $value)

                if ($HaveWildcards) {
                    $ValuesToSelect = Get-SeSelectValue -Element $Element  -All
                    $ValuesToSelect = $ValuesToSelect | Where-Object { $_ -like $Value }
                    if (! $IsMultiSelect) { $ValuesToSelect = $ValuesToSelect | Select -first 1 }
                    Foreach ($v in $ValuesToSelect) {
                        [SeleniumSelection.Option]::SelectByText($Element, $v, $false)     
                    }
                }
                else {
                    [SeleniumSelection.Option]::SelectByText($Element, $value, $false) 
                }
               
            }
            
            { $_ -eq [SeBySelect]::Value } { [SeleniumSelection.Option]::SelectByValue($Element, $value) } 
            { $_ -eq [SeBySelect]::Index } { [SeleniumSelection.Option]::SelectByIndex($Element, $value) }
        }
    }
    catch {
        throw "An error occured checking the selection box, the message was:`r`n $($_.exception.message)"
    }
}
function Set-SeUrl {
    <#
    .SYNOPSIS
    Navigates to the targeted URL with the selected or default driver.

    .DESCRIPTION
    Used for webdriver navigation commands, either to specific target URLs or
    for history (Back/Forward) navigation or refreshing the current page.

    .EXAMPLE
    Set-SeUrl 'https://www.google.com/'

    Directs the default driver to navigate to www.google.com.

    .EXAMPLE
    Set-SeUrl -Refresh

    Reloads the current page for the default driver.

    .EXAMPLE
    Set-SeUrl -Target $Driver -Back

    Directs the targeted webdriver instance to navigate Back in its history.

    .EXAMPLE
    Set-SeUrl -Forward

    Directs the default webdriver to navigate Forward in its history.

    .NOTES
    The Back/Forward/Refresh logic is handled by the webdriver itself. If you
    need a more granular approach to handling which locations are saved or
    retrieved, use Push-SeUrl or Pop-SeUrl to utilise a separately managed
    location stack.
    #>
    [CmdletBinding(DefaultParameterSetName = 'default')]
    param(
        # The target URL for the webdriver to navigate to.
        [Parameter(Mandatory = $true, position = 0, ParameterSetName = 'url')]
        [ValidateURIAttribute()]
        [string]$Url,

        # Trigger the Back history navigation action in the webdriver.
        [Parameter(Mandatory = $true, ParameterSetName = 'back')]
        [switch]$Back,

        # Trigger the Forward history navigation action in the webdriver.
        [Parameter(Mandatory = $true, ParameterSetName = 'forward')]
        [switch]$Forward,

        # Refresh the current page in the webdriver.
        [Parameter(Mandatory = $true, ParameterSetName = 'refresh')]
        [switch]$Refresh,
        
        [Parameter(ParameterSetName = 'back')]
        [Parameter(ParameterSetName = 'forward', Position = 1)]
        [ValidateScript( { $_ -ge 1 })] 
        [Int]$Depth = 1,

        # The target webdriver to manage navigation for. Will utilise the
        # default driver if left unset.
        [Parameter(ValueFromPipeline = $true)]
        [ValidateIsWebDriverAttribute()]
        $Driver 
    )
    Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    for ($i = 0; $i -lt $Depth; $i++) {
        switch ($PSCmdlet.ParameterSetName) {
            'url' { $Driver.Navigate().GoToUrl($Url); break }
            'back' { $Driver.Navigate().Back(); break }
            'forward' { $Driver.Navigate().Forward(); break }
            'refresh' { $Driver.Navigate().Refresh(); break }
            default { throw 'Unexpected ParameterSet' }
        }    
    }
    
}

function Start-SeDriver {
    [cmdletbinding(DefaultParameterSetName = 'default')]
    [OutputType([OpenQA.Selenium.IWebDriver])]
    param(
        #Common to all browsers
        [ArgumentCompleter( { [Enum]::GetNames([SeBrowsers]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBrowsers]) })]
        [Parameter(ParameterSetName = 'Default')]
        $Browser,
        [ValidateURIAttribute()]
        [Parameter(Position = 1)]
        [string]$StartURL,
        [ArgumentCompleter( { [Enum]::GetNames([SeWindowState]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeWindowState]) })]
        [SeWindowState] $State = [SeWindowState]::Default,
        [System.IO.FileInfo]$DefaultDownloadPath,
        [switch]$PrivateBrowsing,
        [int]$ImplicitWait = 10,
        [System.Drawing.Size][SizeTransformAttribute()]$Size,
        [System.Drawing.Point][PointTransformAttribute()]$Position,
        $WebDriverPath,
        $BinaryPath,
        [Parameter(ParameterSetName = 'DriverOptions', Mandatory = $false)]
        [OpenQA.Selenium.DriverService]$Service,
        [Parameter(ParameterSetName = 'DriverOptions', Mandatory = $true)]
        [OpenQA.Selenium.DriverOptions]$Options,
        [Parameter(ParameterSetName = 'Default')]
        [String[]]$Switches,
        [String[]]$Arguments,
        $ProfilePath,
        [OpenQA.Selenium.LogLevel]$LogLevel,
        [ValidateNotNullOrEmpty()]
        $Name 
        # See ParametersToRemove to view parameters that should not be passed to browsers internal implementations.
    )
    process {
        # Exclusive parameters to Start-SeDriver we don't want to pass down to anything else.
        # Still available through the variable directly within this cmdlet
        $ParametersToRemove = @('Arguments', 'Browser', 'Name', 'PassThru')
        $SelectedBrowser = $Browser
        switch ($PSCmdlet.ParameterSetName) {
            'Default' { 
                $Options = New-SeDriverOptions -Browser $Browser
                $PSBoundParameters.Add('Options', $Options) 

            }
            'DriverOptions' {
                if ($PSBoundParameters.ContainsKey('Service')) {
                    $MyService = $PSBoundParameters.Item('Service')
                    foreach ($Key in $MyService.SeParams.Keys) {
                        if (! $PSBoundParameters.ContainsKey($Key)) {
                            $PSBoundParameters.Add($Key, $MyService.SeParams.Item($Key))
                        }
                    }
                }

                $Options = $PSBoundParameters.Item('Options') 
                $SelectedBrowser = $Options.SeParams.Browser

                # Start-SeDrivers params overrides whatever is in the options. 
                # Any options parameter not specified by Start-SeDriver get added to the psboundparameters
                foreach ($Key in $Options.SeParams.Keys) {
                    if (! $PSBoundParameters.ContainsKey($Key)) {
                        $PSBoundParameters.Add($Key, $Options.SeParams.Item($Key))
                    }
                }

            }
        }

        if ($PSBoundParameters.ContainsKey('Arguments')) {
            foreach ($Argument in $Arguments) {
                $Options.AddArguments($Argument)
            }
        }

        
        $FriendlyName = $null
        if ($PSBoundParameters.ContainsKey('Name')) { 
            $FriendlyName = $Name 
       
            $AlreadyExist = $Script:SeDrivers.Where( { $_.SeFriendlyName -eq $FriendlyName }, 'first').Count -gt 0
            if ($AlreadyExist) {
                throw "A driver with the name $FriendlyName is already in the active list of started driver."
            }
        }
       

        #Remove params exclusive to this cmdlet before going further.
        $ParametersToRemove | ForEach-Object { if ($PSBoundParameters.ContainsKey("$_")) { [void]($PSBoundParameters.Remove("$_")) } }

        switch ($SelectedBrowser) {
            'Chrome' { $Driver = Start-SeChromeDriver @PSBoundParameters; break }
            'Edge' { $Driver = Start-EdgeDriver @PSBoundParameters; break }
            'Firefox' { $Driver = Start-SeFirefoxDriver @PSBoundParameters; break }
            'InternetExplorer' { $Driver = Start-SeInternetExplorerDriver @PSBoundParameters; break }
            'MSEdge' { $Driver = Start-SeMSEdgeDriver @PSBoundParameters; break }
        }
        if ($null -ne $Driver) {
            if ($null -eq $FriendlyName) { $FriendlyName = $Driver.SessionId } 
            Write-Verbose -Message "Opened $($Driver.Capabilities.browsername) $($Driver.Capabilities.ToDictionary().browserVersion)"

            #Se prefix used to avoid clash with anything from Selenium in the future
            #SessionId scriptproperty validation to avoid perfomance cost of checking closed session.
            $Headless = if ($state -eq [SeWindowState]::Headless) { " (headless)" } else { "" }
            $mp = @{InputObject = $Driver ; MemberType = 'NoteProperty' }
            Add-Member @mp -Name 'SeBrowser' -Value "$SelectedBrowser$($Headless)"
            Add-Member @mp -Name 'SeFriendlyName' -Value "$FriendlyName"  
            Add-Member @mp -Name 'SeSelectedElements' -Value $null


            $Script:SeDrivers.Add($Driver)
            Return Select-SeDriver -Name $FriendlyName
        }

    }
}

function Start-SeRemote {
    [cmdletbinding(DefaultParameterSetName = 'default')]
    param(
        [string]$RemoteAddress,
        [hashtable]$DesiredCapabilities,
        [ValidateURIAttribute()]
        [Parameter(Position = 0)]
        [string]$StartURL,
        [int]$ImplicitWait = 10,
        [System.Drawing.Size][SizeTransformAttribute()]$Size,
        [System.Drawing.Point][PointTransformAttribute()]$Position
    )

    $desired = [OpenQA.Selenium.Remote.DesiredCapabilities]::new()
    if (-not $DesiredCapabilities.Name) {
        $desired.SetCapability('name', [datetime]::now.tostring("yyyyMMdd-hhmmss"))
    }
    foreach ($k in $DesiredCapabilities.keys) { $desired.SetCapability($k, $DesiredCapabilities[$k]) }
    $Driver = [OpenQA.Selenium.Remote.RemoteWebDriver]::new($RemoteAddress, $desired)

    if (-not $Driver) { Write-Warning "Web driver was not created"; return }

    if ($PSBoundParameters.ContainsKey('Size')) { $Driver.Manage().Window.Size = $Size }
    if ($PSBoundParameters.ContainsKey('Position')) { $Driver.Manage().Window.Position = $Position }
    $Driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds($ImplicitWait)
    if ($StartURL) { $Driver.Navigate().GotoUrl($StartURL) }

    return $Driver
}
function Stop-SeDriver { 
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [OpenQA.Selenium.IWebDriver]
        $Driver
    )
    Begin {
        $ElementsToRemove = [System.Collections.Generic.List[PSObject]]::new()
        $TextInfo = (Get-Culture).TextInfo 
    }
    Process {
        if (! $PSBoundParameters.ContainsKey('Driver')) {
            $Driver = $script:SeDriversCurrent
        }


        if ($null -ne $Driver) {
            $BrowserName = $TextInfo.ToTitleCase($Driver.Capabilities.browsername)

            if ($null -eq $Driver.SessionId) {
                Write-Warning "$BrowserName Driver already closed"
                if ($ElementsToRemove.contains($Driver)) { $ElementsToRemove.Add($Driver) }
                
            }
            else {
                Write-Verbose -Message "Closing $BrowserName $($Driver.SeFriendlyName )..."
            
                $Driver.Close()
                $Driver.Dispose()
                $ElementsToRemove.Add($Driver)    
            }

            
      
       
        }
        
    }
    End {
        $ElementsToRemove | ForEach-Object { [void]($script:SeDrivers.Remove($_)) }
        $script:SeDriversCurrent = $null
    }
    

  
}
function Switch-SeFrame {
    param (
        [Parameter(Mandatory = $true, ParameterSetName = 'Frame', Position = 0)]
        $Frame,

        [Parameter(Mandatory = $true, ParameterSetName = 'Parent')]
        [switch]$Parent,

        [Parameter(Mandatory = $true, ParameterSetName = 'Root')]
        [switch]$Root,
        [Parameter(ValueFromPipeline = $true)]
        [ValidateIsWebDriverAttribute()]
        $Driver
    )
    Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    #TODO Frame validation... Do not try to switch if element does not exist ?
    #TODO Review ... Maybe Parent / Root should be a unique parameter : -Level Parent/Root )
    if ($frame) { [void]$Driver.SwitchTo().Frame($Frame) }
    elseif ($Parent) { [void]$Driver.SwitchTo().ParentFrame() }
    elseif ($Root) { [void]$Driver.SwitchTo().defaultContent() }
}
function Switch-SeWindow {
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [OpenQA.Selenium.IWebDriver]
        $Driver,

        [Parameter(Mandatory = $true)]$Window
    )
    begin {
        Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    }
    process {
        $Driver.SwitchTo().Window($Window) | Out-Null
    }
}
function Wait-SeDriver {
    [Cmdletbinding()]
    param(
        [ArgumentCompleter([SeDriverConditionsCompleter])]
        [ValidateScript( { Get-SeDriverConditionsValidation -Condition $_ })]
        [Parameter(Mandatory = $true, Position = 0)]
        $Condition,
        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateScript( { Get-SeDriverConditionsValueValidation -Condition $Condition -Value $_ })]
        [ValidateNotNull()]
        $Value,

        #Specifies a time out
        [Parameter(Position = 2)]
        [Int]$Timeout = 3,
        #The driver or Element where the search should be performed.
        [Parameter(Position = 3, ValueFromPipeline = $true)]
        $Driver
        
    )
    Begin {
        Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    }
    process {
     
        $WebDriverWait = [OpenQA.Selenium.Support.UI.WebDriverWait]::new($Driver, (New-TimeSpan -Seconds $Timeout))
        $SeCondition = [OpenQA.Selenium.Support.UI.ExpectedConditions]::$Condition($Value)
        
        try {
            [void]($WebDriverWait.Until($SeCondition))
            return $true
        }
        catch {
            Write-Error $_
            return $false
        }
    }
}





Register-ArgumentCompleter -CommandName Command-Name -ParameterName Name -ScriptBlock $MyArgumentCompletion
function Wait-SeElement {
    [Cmdletbinding(DefaultParameterSetName = 'Element')]
    param(
        [ArgumentCompleter( { [Enum]::GetNames([SeBySelector]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBySelector]) })]
        [Parameter(ParameterSetName = 'Locator', Position = 0, Mandatory = $true)]
        [SeBySelector]$By = [SeBySelector]::XPath,
        [Parameter(Position = 1, Mandatory = $true, ParameterSetName = 'Locator')]
        [string]$Value,

        [Parameter(ParameterSetName = 'Element', Mandatory = $true)]
        [OpenQA.Selenium.IWebElement]$Element,
        [ArgumentCompleter([SeElementsConditionsCompleter])]
        [ValidateScript( { Get-SeElementsConditionsValidation -Condition $_ -By $By })]
        $Condition,
        [ValidateScript( { Get-SeElementsConditionsValueValidation -By $By -Element $Element -Condition $Condition -ConditionValue $_ })]
        [ValidateNotNull()]
        $ConditionValue,
        
     
        #Specifies a time out
        [Int]$Timeout = 3,
        #The driver or Element where the search should be performed.
        [Parameter( ValueFromPipeline = $true)]
        $Driver

    )
    begin {
        Init-SeDriver -Driver ([ref]$Driver) -ErrorAction Stop
    }
    process {
        $ExpectedValueType = Get-SeElementsConditionsValueType -text $Condition

        #Manage ConditionValue not provided when expected
        if (! $PSBoundParameters.ContainsKey('ConditionValue')) {
            if ($null -ne $ExpectedValueType) {
                Write-Error "The $Condtion condtion does expect a ConditionValue of type $ExpectedValueType (None provided)."
                return $null
            }
        }

        $WebDriverWait = [OpenQA.Selenium.Support.UI.WebDriverWait]::new($Driver, (New-TimeSpan -Seconds $Timeout))
        #
        $NoExtraArg = $null -eq $ExpectedValueType
        if ($PSBoundParameters.ContainsKey('Element')) {
            if ($NoExtraArg) {
                $SeCondition = [OpenQA.Selenium.Support.UI.ExpectedConditions]::$Condition($Element)
            }
            else {
                $SeCondition = [OpenQA.Selenium.Support.UI.ExpectedConditions]::$Condition($Element, $ConditionValue)
            }
        }
        else {
            if ($NoExtraArg) {
                $SeCondition = [OpenQA.Selenium.Support.UI.ExpectedConditions]::$Condition([OpenQA.Selenium.By]::$By($Value))
            }
            else {
                $SeCondition = [OpenQA.Selenium.Support.UI.ExpectedConditions]::$Condition([OpenQA.Selenium.By]::$By($Value), $ConditionValue)
            }
        }

        
     


        try {
            [void]($WebDriverWait.Until($SeCondition))
            return $true
        }
        catch {
            Write-Error $_
            return $false
        }
         
                
        
    }
}




Function Get-OptionsSwitchValue($Switches, $Name) {
    if ($null -eq $Switches -or -not $Switches.Contains($Name)) { Return $false }
    return $True
}
Function Get-WildcardsIndices($Value) {
   
    $Escape = 0
    $Index = -1 
    $Value.ToCharArray() | ForEach-Object {
        $Index += 1
        $IsWildCard = $false
        switch ($_) {
            '`' { $Escape += 1; break }
            '*' { $IsWildCard = $Escape % 2 -eq 0; $Escape = 0 }
            Default { $Escape = 0 }
        }
        if ($IsWildCard) { return $Index }
 
    }
}
function Init-SeDriver {
    [CmdletBinding()]
    param (
        [ref]$Driver
    )
    
    if ($null -ne $Driver.Value) { return }
    if ($null -ne $script:SeDriversCurrent) { 
        $Driver.Value = $script:SeDriversCurrent
        return 
    }
    Throw [System.ArgumentNullException]::new("A driver need to be explicitely specified or implicitely available.")

    
    
}
function Start-SeChromeDriver {
    [cmdletbinding(DefaultParameterSetName = 'default')]
    param(
      
        [ValidateURIAttribute()]
        [Parameter(Position = 1)]
        [string]$StartURL,
        [ArgumentCompleter( { [Enum]::GetNames([SeWindowState]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeWindowState]) })]
        $State,
        [System.IO.FileInfo]$DefaultDownloadPath,
        [switch]$PrivateBrowsing,
        [int]$ImplicitWait = 10,
        [System.Drawing.Size]$Size,
        [System.Drawing.Point]$Position,
        $WebDriverPath = $env:ChromeWebDriver,
        $BinaryPath,
        [OpenQA.Selenium.DriverService]$service,
        [OpenQA.Selenium.DriverOptions]$Options,
        [String[]]$Switches,
        [OpenQA.Selenium.LogLevel]$LogLevel
        


        #        [System.IO.FileInfo]$ProfilePath,
        #        $BinaryPath,
    
        # "user-data-dir=$ProfilePath"


    
    )

    process {
        #Additional Switches 
        $EnablePDFViewer = Get-OptionsSwitchValue -Switches $Switches -Name  'EnablePDFViewer'
        $DisableAutomationExtension = Get-OptionsSwitchValue -Switches $Switches -Name 'DisableAutomationExtension'

        #region Process Additional Switches
        if ($EnablePDFViewer) { $Options.AddUserProfilePreference('plugins', @{'always_open_pdf_externally' = $true; }) }

        if ($DisableAutomationExtension) {
            $Options.AddAdditionalCapability('useAutomationExtension', $false)
            $Options.AddExcludedArgument('enable-automation')
        }

        #endregion

        if ($DefaultDownloadPath) {
            Write-Verbose "Setting Default Download directory: $DefaultDownloadPath"
            $Options.AddUserProfilePreference('download', @{'default_directory' = $($DefaultDownloadPath.FullName); 'prompt_for_download' = $false; })
        }

        if ($ProfilePath) {
            Write-Verbose "Setting Profile directory: $ProfilePath"
            $Options.AddArgument("user-data-dir=$ProfilePath")
        }

        if ($BinaryPath) {
            Write-Verbose "Setting Chrome Binary directory: $BinaryPath"
            $Options.BinaryLocation = "$BinaryPath"
        }

        if ($PSBoundParameters.ContainsKey('LogLevel')) {
            Write-Warning "LogLevel parameter is not implemented for $($Options.SeParams.Browser)"
        }

       

        switch ($State) {
            { $_ -eq [SeWindowState]::Headless } { $Options.AddArguments('headless') }
            #  { $_ -eq [SeWindowState]::Minimized } {}  # No switches... Managed after launch
            { $_ -eq [SeWindowState]::Maximized } { $Options.AddArguments('start-maximized') }
            { $_ -eq [SeWindowState]::Fullscreen } { $Options.AddArguments('start-fullscreen') }
        }
      
        if ($PrivateBrowsing) {
            $Options.AddArguments('Incognito')
        }
        #  $Location = @('--window-position=1921,0', '--window-size=1919,1080')
        if ($PSBoundParameters.ContainsKey('Size')) { 
            $Options.AddArguments("--window-size=$($Size.Width),$($Size.Height)")
        }
        if ($PSBoundParameters.ContainsKey('Position')) {
            $Options.AddArguments("--window-position=$($Position.X),$($Position.Y)")
        }
        

       
        if (-not $PSBoundParameters.ContainsKey('Service')) {
            $ServiceParams = @{}
            if ($WebDriverPath) { $ServiceParams.Add('WebDriverPath', $WebDriverPath) }
            $service = New-SeDriverService -Browser Chrome @ServiceParams
        }
        

        
        $Driver = [OpenQA.Selenium.Chrome.ChromeDriver]::new($service, $Options)
        if (-not $Driver) { Write-Warning "Web driver was not created"; return }

        #region post creation options
        $Driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds($ImplicitWait)

        if ($State -eq 'Minimized') {
            $Driver.Manage().Window.Minimize();
        }

        if ($Headless -and $DefaultDownloadPath) {
            $HeadlessDownloadParams = [system.collections.generic.dictionary[[System.String], [System.Object]]]::new()
            $HeadlessDownloadParams.Add('behavior', 'allow')
            $HeadlessDownloadParams.Add('downloadPath', $DefaultDownloadPath.FullName)
            $Driver.ExecuteChromeCommand('Page.setDownloadBehavior', $HeadlessDownloadParams)
        }

        if ($StartURL) { $Driver.Navigate().GoToUrl($StartURL) }
        #endregion


        return $Driver
    }
}

function Start-SeEdgeDriver {
    param(
        [ArgumentCompleter( { [Enum]::GetNames([SeBrowsers]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBrowsers]) })]
        $Browser,
        [ValidateURIAttribute()]
        [Parameter(Position = 1)]
        [string]$StartURL,
        [ArgumentCompleter( { [Enum]::GetNames([SeWindowState]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeWindowState]) })]
        $State,
        [System.IO.FileInfo]$DefaultDownloadPath,
        [switch]$PrivateBrowsing,
        [int]$ImplicitWait = 10,
        [System.Drawing.Size]$Size,
        [System.Drawing.Point]$Position,
        $WebDriverPath,
        $BinaryPath,
        [OpenQA.Selenium.DriverService]$service,
        [OpenQA.Selenium.DriverOptions]$Options,
        [String[]]$Switches,
        [OpenQA.Selenium.LogLevel]$LogLevel

    )
    $OptionSettings = @{ browserName = '' }
    #region check / set paths for browser and web driver and edge options
    if ($PSBoundParameters['BinaryPath'] -and -not (Test-Path -Path $BinaryPath)) {
        throw "Could not find $BinaryPath"; return
    }

    if ($PSBoundParameters.ContainsKey('LogLevel')) {
        Write-Warning "LogLevel parameter is not implemented for $($Options.SeParams.Browser)"
    }

    #Were we given a driver location and is msedgedriver there ?
    #If were were given a location (which might be from an environment variable) is the driver THERE ?
    # if not, were we given a path for the browser executable, and is the driver THERE ?
    # and if not there either, is there one in the assemblies sub dir ? And if not bail
    if ($WebDriverPath -and -not (Test-Path -Path (Join-Path -Path $WebDriverPath -ChildPath 'msedgedriver.exe'))) {
        throw "Could not find msedgedriver.exe in $WebDriverPath"; return
    }
    elseif ($WebDriverPath -and (Test-Path (Join-Path -Path $WebDriverPath -ChildPath 'msedge.exe'))) {
        Write-Verbose -Message "Using browser from $WebDriverPath"
        $optionsettings['BinaryLocation'] = Join-Path -Path $WebDriverPath -ChildPath 'msedge.exe'
    }
    elseif ($BinaryPath) {
        $optionsettings['BinaryLocation'] = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BinaryPath)
        $binaryDir = Split-Path -Path $BinaryPath -Parent
        Write-Verbose -Message "Will request $($OptionSettings['BinaryLocation']) as the browser"
    }
    if (-not $WebDriverPath -and $binaryDir -and (Test-Path (Join-Path -Path $binaryDir -ChildPath 'msedgedriver.exe'))) {
        $WebDriverPath = $binaryDir
    }
    # No linux or mac driver to test for yet
    if (-not $WebDriverPath -and (Test-Path (Join-Path -Path "$PSScriptRoot\Assemblies\" -ChildPath 'msedgedriver.exe'))) {
        $WebDriverPath = "$PSScriptRoot\Assemblies\"
        Write-Verbose -Message "Using Web driver from the default location"
    }
    if (-not $WebDriverPath) { throw "Could not find msedgedriver.exe"; return }

    
    if (-not $PSBoundParameters.ContainsKey('Service')) {
        $ServiceParams = @{}
        if ($WebDriverPath) { $ServiceParams.Add('WebDriverPath', $WebDriverPath) }
        $service = New-SeDriverService -Browser Edge @ServiceParams
    }
    
    $options = New-Object -TypeName OpenQA.Selenium.Chrome.ChromeOptions -Property $OptionSettings
    
    #The command line args may now be --inprivate --headless but msedge driver V81 does not pass them
    if ($PrivateBrowsing) { $options.AddArguments('InPrivate') }
    if ($State -eq [SeWindowState]::Headless) { $options.AddArguments('headless') }
    if ($ProfilePath) {
        $ProfilePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ProfilePath)
        Write-Verbose "Setting Profile directory: $ProfilePath"
        $options.AddArgument("user-data-dir=$ProfilePath")
    }
    if ($DefaultDownloadPath) {
        $DefaultDownloadPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DefaultDownloadPath)
        Write-Verbose "Setting Default Download directory: $DefaultDownloadPath"
        $Options.AddUserProfilePreference('download', @{'default_directory' = $DefaultDownloadPath; 'prompt_for_download' = $false; })
    }
    #endregion

    $Driver = [OpenQA.Selenium.Chrome.ChromeDriver]::new($service, $options)

    #region post driver checks and option checks If we have a version know to have problems with passing arguments, generate a warning if we tried to send any.
    if (-not $Driver) {
        Write-Warning "Web driver was not created"; return
    }
    else {
        $driverversion = $Driver.Capabilities.ToDictionary().msedge.msedgedriverVersion -replace '^([\d.]+).*$', '$1'
        if (-not $driverversion) { $driverversion = $driver.Capabilities.ToDictionary().chrome.chromedriverVersion -replace '^([\d.]+).*$', '$1' }
        Write-Verbose "Web Driver version $driverversion"
        Write-Verbose ("Browser: {0,9} {1}" -f $Driver.Capabilities.ToDictionary().browserName,
            $Driver.Capabilities.ToDictionary().browserVersion)
        
        $browserCmdline = (Get-CimInstance -Verbose:$false -Query (
                "Select * From win32_process " +
                "Where parentprocessid = $($service.ProcessId) " +
                "And name = 'msedge.exe'")).commandline
        $options.arguments | Where-Object { $browserCmdline -notlike "*$_*" } | ForEach-Object {
            Write-Warning "Argument $_ was not passed to the Browser. This is a known issue with some web driver versions."
        }
    }

    if ($PSBoundParameters.ContainsKey('Size')) { $Driver.Manage().Window.Size = $Size }
    if ($PSBoundParameters.ContainsKey('Position')) { $Driver.Manage().Window.Position = $Position }

    $Driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds($ImplicitWait)
    if ($StartURL) { $Driver.Navigate().GoToUrl($StartURL) }


    switch ($State) {
        { $_ -eq [SeWindowState]::Minimized } { $Driver.Manage().Window.Minimize(); }
        { $_ -eq [SeWindowState]::Maximized } { $Driver.Manage().Window.Maximize() }
        { $_ -eq [SeWindowState]::Fullscreen } { $Driver.Manage().Window.FullScreen() }
    }

 
    #endregion

    return  $Driver
}
function Start-SeFirefoxDriver {
    [cmdletbinding(DefaultParameterSetName = 'default')]
    param(
        [ArgumentCompleter( { [Enum]::GetNames([SeBrowsers]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBrowsers]) })]
        $Browser,
        [ValidateURIAttribute()]
        [Parameter(Position = 1)]
        [string]$StartURL,
        [ArgumentCompleter( { [Enum]::GetNames([SeWindowState]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeWindowState]) })]
        [SeWindowState]$State,
        [System.IO.FileInfo]$DefaultDownloadPath,
        [switch]$PrivateBrowsing,
        [int]$ImplicitWait = 10,
        [System.Drawing.Size]$Size,
        [System.Drawing.Point]$Position,
        $WebDriverPath = $env:GeckoWebDriver,
        $BinaryPath,
        [OpenQA.Selenium.DriverService]$service,
        [OpenQA.Selenium.DriverOptions]$Options,
        [String[]]$Switches,
        [OpenQA.Selenium.LogLevel]$LogLevel
        
    )
    process {
        #region firefox set-up options
        $Firefox_Options = [OpenQA.Selenium.Firefox.FirefoxOptions]::new()

        if ($State -eq [SeWindowState]::Headless) {
            $Firefox_Options.AddArguments('-headless')
        }

        if ($DefaultDownloadPath) {
            Write-Verbose "Setting Default Download directory: $DefaultDownloadPath"
            $Firefox_Options.setPreference("browser.download.folderList", 2);
            $Firefox_Options.SetPreference("browser.download.dir", "$DefaultDownloadPath");
        }

        if ($PrivateBrowsing) {
            $Firefox_Options.SetPreference("browser.privatebrowsing.autostart", $true)
        }

        if ($PSBoundParameters.ContainsKey('LogLevel')) {
            Write-Verbose "Setting Firefox LogLevel to $LogLevel"
            $Options.LogLevel = $LogLevel
        }

        if (-not $PSBoundParameters.ContainsKey('Service')) {
            $ServiceParams = @{}
            if ($WebDriverPath) { $ServiceParams.Add('WebDriverPath', $WebDriverPath) }
            $service = New-SeDriverService -Browser Firefox @ServiceParams
        }


        $Driver = [OpenQA.Selenium.Firefox.FirefoxDriver]::new($service, $Firefox_Options)
        if (-not $Driver) { Write-Warning "Web driver was not created"; return }

        #region post creation options
        $Driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds($ImplicitWait)

        if ($PSBoundParameters.ContainsKey('Size')) { $Driver.Manage().Window.Size = $Size }
        if ($PSBoundParameters.ContainsKey('Position')) { $Driver.Manage().Window.Position = $Position }

        # [SeWindowState]
        switch ($State) {
            { $_ -eq [SeWindowState]::Minimized } { $Driver.Manage().Window.Minimize(); break }
            { $_ -eq [SeWindowState]::Maximized } { $Driver.Manage().Window.Maximize() ; break }
            { $_ -eq [SeWindowState]::Fullscreen } { $Driver.Manage().Window.FullScreen() ; break }
        }
        
        if ($StartURL) { $Driver.Navigate().GoToUrl($StartURL) }
        #endregion

        Return $Driver
    }
}
function Start-SeInternetExplorerDriver {
    param(
        [ArgumentCompleter( { [Enum]::GetNames([SeBrowsers]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBrowsers]) })]
        $Browser,
        [ValidateURIAttribute()]
        [Parameter(Position = 1)]
        [string]$StartURL,
        [ArgumentCompleter( { [Enum]::GetNames([SeWindowState]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeWindowState]) })]
        $State,
        [System.IO.FileInfo]$DefaultDownloadPath,
        [switch]$PrivateBrowsing,
        [int]$ImplicitWait = 10,
        [System.Drawing.Size]$Size,
        [System.Drawing.Point]$Position,
        $WebDriverPath,
        $BinaryPath,
        [OpenQA.Selenium.DriverService]$service,
        [OpenQA.Selenium.DriverOptions]$Options,
        [String[]]$Switches,
        [OpenQA.Selenium.LogLevel]$LogLevel
    )

    $IgnoreProtectedModeSettings = Get-OptionsSwitchValue -Switches $Switches -Name  'IgnoreProtectedModeSettings'
    #region IE set-up options
    if ($state -eq [SeWindowState]::Headless -or $PrivateBrowsing) { Write-Warning 'The Internet explorer driver does not support headless or Inprivate operation; these switches are ignored' }

    $InternetExplorer_Options = [OpenQA.Selenium.IE.InternetExplorerOptions]::new()
    $InternetExplorer_Options.IgnoreZoomLevel = $true
    if ($IgnoreProtectedModeSettings) {
        $InternetExplorer_Options.IntroduceInstabilityByIgnoringProtectedModeSettings = $true
    }

    if ($StartURL) { $InternetExplorer_Options.InitialBrowserUrl = $StartURL }
    
    if (-not $PSBoundParameters.ContainsKey('Service')) {
        $ServiceParams = @{}
        if ($WebDriverPath) { $ServiceParams.Add('WebDriverPath', $WebDriverPath) }
        $service = New-SeDriverService -Browser InternetExplorer @ServiceParams
    }
    
    #endregion

    $Driver = [OpenQA.Selenium.IE.InternetExplorerDriver]::new($service, $InternetExplorer_Options)
    if (-not $Driver) { Write-Warning "Web driver was not created"; return }

    if ($PSBoundParameters.ContainsKey('LogLevel')) {
        Write-Warning "LogLevel parameter is not implemented for $($Options.SeParams.Browser)"
    }

    #region post creation options
    if ($PSBoundParameters.ContainsKey('Size')) { $Driver.Manage().Window.Size = $Size }
    if ($PSBoundParameters.ContainsKey('Position')) { $Driver.Manage().Window.Position = $Position }
    $Driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds($ImplicitWait)

    
    switch ($State) {
        { $_ -eq [SeWindowState]::Minimized } { $Driver.Manage().Window.Minimize(); }
        { $_ -eq [SeWindowState]::Maximized } { $Driver.Manage().Window.Maximize() }
        { $_ -eq [SeWindowState]::Fullscreen } { $Driver.Manage().Window.FullScreen() }
    }

    #endregion

    return $Driver
}
function Start-SeMSEdgeDriver {
    param(
        [ArgumentCompleter( { [Enum]::GetNames([SeBrowsers]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeBrowsers]) })]
        $Browser,
        [ValidateURIAttribute()]
        [Parameter(Position = 1)]
        [string]$StartURL,
        [ArgumentCompleter( { [Enum]::GetNames([SeWindowState]) })]
        [ValidateScript( { $_ -in [Enum]::GetNames([SeWindowState]) })]
        $State,
        [System.IO.FileInfo]$DefaultDownloadPath,
        [switch]$PrivateBrowsing,
        [int]$ImplicitWait = 10,
        [System.Drawing.Size]$Size,
        [System.Drawing.Point]$Position,
        $WebDriverPath,
        $BinaryPath,
        [OpenQA.Selenium.DriverService]$service,
        [OpenQA.Selenium.DriverOptions]$Options,
        [String[]]$Switches,
        [OpenQA.Selenium.LogLevel]$LogLevel
    )
    #region Edge set-up options
    if ($state -eq [SeWindowState]::Headless) { Write-Warning 'Pre-Chromium Edge does not support headless operation; the Headless switch is ignored' }
    
    if (-not $PSBoundParameters.ContainsKey('Service')) {
        $ServiceParams = @{}
        #if ($WebDriverPath) { $ServiceParams.Add('WebDriverPath', $WebDriverPath) }
        $service = New-SeDriverService -Browser MSEdge @ServiceParams
    }
    
    $options = [OpenQA.Selenium.Edge.EdgeOptions]::new()

    if ($PrivateBrowsing) { $options.UseInPrivateBrowsing = $true }
    if ($StartURL) { $options.StartPage = $StartURL }
    #endregion

    if ($PSBoundParameters.ContainsKey('LogLevel')) {
        Write-Warning "LogLevel parameter is not implemented for $($Options.SeParams.Browser)"
    }

    try {
        $Driver = [OpenQA.Selenium.Edge.EdgeDriver]::new($service , $options)
    }
    catch {
        $driverversion = (Get-Item .\assemblies\MicrosoftWebDriver.exe).VersionInfo.ProductVersion
        $WindowsVersion = [System.Environment]::OSVersion.Version.ToString()
        Write-Warning -Message "Edge driver is $driverversion. Windows is $WindowsVersion. If the driver is out-of-date, update it as a Windows feature,`r`nand then delete $PSScriptRoot\assemblies\MicrosoftWebDriver.exe"
        throw $_ ; return
    }
    if (-not $Driver) { Write-Warning "Web driver was not created"; return }

    #region post creation options
    if ($PSBoundParameters.ContainsKey('Size')) { $Driver.Manage().Window.Size = $Size }
    if ($PSBoundParameters.ContainsKey('Position')) { $Driver.Manage().Window.Position = $Position }
    $Driver.Manage().Timeouts().ImplicitWait = [TimeSpan]::FromSeconds($ImplicitWait)

    switch ($State) {
        { $_ -eq [SeWindowState]::Minimized } { $Driver.Manage().Window.Minimize() }
        { $_ -eq [SeWindowState]::Maximized } { $Driver.Manage().Window.Maximize() }
        { $_ -eq [SeWindowState]::Fullscreen } { $Driver.Manage().Window.FullScreen() }
    }

    #endregion

    Return $Driver
}
function ValidateURL {
    param(
        [Parameter(Mandatory = $true)]
        $URL
    )
    $Out = $null
    #TODO Support for URL without https (www.google.ca) / add it ?
    [uri]::TryCreate($URL, [System.UriKind]::Absolute, [ref]$Out)
}
