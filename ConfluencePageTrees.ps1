<#
Typical flow

$a = Get-CHeader
RecursiveCopy-CPage -pHeaders $a -pBase_Uri $__base_uri -pPage_id xxxxx
RecursiveDelete-CPage -pHeaders $a -pBase_Uri $__base_uri -pPage_id yyyyy
#>

# Get login details, encode them and put them into the header.
function Get-CHeader {
    $creds = Get-Credential
    $user = $creds.UserName
    $pass = $creds.GetNetworkCredential().Password
    $pair = $user + ':' + $pass
    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
    $basicAuthValue = "Basic $encodedCreds"
    $Headers = @{
        Authorization = $basicAuthValue
        }
    Write-Output $Headers
}

# Copy a page-tree
function RecursiveCopy-CPage
{
    Param ([hashtable]$pHeaders, [string]$pBase_Uri, [int]$pPage_id, [int]$pAncestor_id)

    # Get the page to be copied
    $original_page = Invoke-RestMethod -Uri ($pBase_Uri+"content/"+$pPage_id+"?expand=body.storage,ancestors,space,children.page") -Method get -ContentType "application/json" -Headers $pHeaders
    # Pick out the properties needed
    $new_page = New-Object psobject

    # Note the pages in the new page tree get the same title as the original + ' (nyr)'
    $new_page | Add-member -MemberType NoteProperty -Name title -Value ($original_page.title + " (nyr)")
    $new_page | Add-member -MemberType NoteProperty -Name type -Value $original_page.type
    $new_page | Add-member -MemberType NoteProperty -Name space -Value $original_page.space
    $new_page | Add-member -MemberType NoteProperty -Name body -Value $original_page.body

    # $pAncestor_id undefined means that this is the topmost page to be copied, we ancor the new page next to it
    if (!$pAncestor_id)
    {
        $new_page | Add-member -MemberType NoteProperty -Name ancestors -Value $original_page.ancestors
    }
    else
    {
        $new_page | Add-member -MemberType NoteProperty -Name ancestors -Value @(@{id="$pAncestor_id";type="page"})
    }

    $new_page_json = ConvertTo-Json $new_page
    $created_page = Invoke-RestMethod -Uri ($pBase_uri+"content/") -Method Post -ContentType "application/json" -Body $new_page_json -Headers $pHeaders

    # Loop through the children, copy them and attach to the newly created page
    foreach ($p_id in $original_page.children.page.results.GetEnumerator()) 
    {
        RecursiveCopy-CPage -pHeader $pHeaders -pBase_Uri $pBase_Uri -pPage_id $p_id.id -pAncestor_id $created_page.id
    }
}



# Utility functions
# Remove a page-tree
function RecursiveDelete-CPage
{
    Param ([hashtable]$pHeaders, [string]$pBase_uri, [int]$pPage_id)
    
    # Get the top page of the page-tree to be deleted
    $original = Invoke-RestMethod -Uri ($pBase_Uri+"content/"+$pPage_id+"?expand=children.page") -Method get -ContentType "application/json" -Headers $pHeaders

    # Go down to the leaves and move back up deleting the tree as you go
    foreach ($child in $original.children.page.results.GetEnumerator()) 
    {
        RecursiveDelete-CPage -pHeader $pHeaders -pBase_Uri $pBase_Uri -pPage_id $child.id 
    }

    # Arrived at a leave, delete it
    Invoke-RestMethod -Uri ($pBase_uri+"content/"+$original.id) -Method Delete -ContentType "application/json" -Headers $pHeaders
}