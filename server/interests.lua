OrganizationInterests = {}
local Ok,Err=Organizations.Ok,Organizations.Err
local function IsCallable(value)
    return type(value)=='function' or (type(value)=='table' and type(rawget(value,'__cfx_functionReference'))=='string')
end
function OrganizationInterests.CharacterProvider()
    local called,result=pcall(function() return exports['feather-core']:GetProvider('character-profile',nil,1) end)
    if not called or type(result)~='table' or not result.ok or type(result.value)~='table'
        or type(result.value.provider)~='table' or result.value.provider.owner~='feather-character'
        or type(result.value.implementation)~='table' or not IsCallable(result.value.implementation.GetProfile) then
        return Err('dependency_unavailable','Character profile provider Contract 1 is required.')
    end
    local checked,health=pcall(function() return exports['feather-core']:GetProviderHealth('character-profile',result.value.provider.name) end)
    if not checked or type(health)~='table' or not health.ok or type(health.value)~='table' or health.value.state~='ready' then
        return Err('dependency_unavailable','Character profile provider is not ready.')
    end
    return Ok(result.value.implementation)
end
function OrganizationInterests.CharacterSnapshot(result,holderId)
    if type(result)~='table' then return Err('invalid_dependency_result','Character provider returned an invalid result.') end
    if result.ok~=true then
        if result.ok==false and result.code=='not_found' then return Err('holder_not_found','Character holder not found.') end
        return Err('dependency_unavailable','Character holder lookup failed.')
    end
    local value=result.value
    if type(value)~='table' or not Organizations.Uuid(value.characterId) or value.characterId:lower()~=holderId
        or type(value.status)~='string' then return Err('invalid_dependency_result','Character identity does not match requested holder.') end
    if value.status~='active' then return Err('holder_inactive','Character holder is not active.') end
    return Ok({holderType='character',holderId=holderId,status='active'})
end
-- Internal resolver, not a public enumeration API. Future grant/revoke handlers
-- must authorize target ownership first and revalidate within their write flow.
function OrganizationInterests.ResolveHolder(request,resource)
    local allowed=Organizations.CheckRead(resource)
    if not allowed.ok then return allowed end
    if type(request)~='table' or not Organizations.Uuid(request.holderId)
        or (request.holderType~='character' and request.holderType~='organization') then
        return Err('invalid_input','Character/organization holder and UUID required.')
    end
    for key in pairs(request) do
        if key~='holderType' and key~='holderId' then return Err('invalid_input','Unexpected holder field.') end
    end
    local holderType,holderId=request.holderType,request.holderId:lower()
    if holderType=='organization' then
        local found=OrganizationIdentity.Get({organizationId=holderId},resource)
        if not found.ok then
            if found.code=='organization_not_found' then return Err('holder_not_found','Organization holder not found.') end
            return found
        end
        if found.value.status~='active' then return Err('holder_inactive','Organization holder must be active.') end
        return Ok({holderType=holderType,holderId=holderId,status=found.value.status})
    end
    local provider=OrganizationInterests.CharacterProvider()
    if not provider.ok then return provider end
    local called,result=pcall(provider.value.GetProfile,holderId)
    if not called then return Err('dependency_unavailable','Character holder lookup failed.') end
    return OrganizationInterests.CharacterSnapshot(result,holderId)
end
local catalog={
    {key='founder',label='Founder',holderTypes={'character'}},
    {key='owner',label='Owner',holderTypes={'character','organization'}},
    {key='controlling_organization',label='Controlling Organization',holderTypes={'organization'}}
}
function OrganizationInterests.Types(resource)
    local allowed=Organizations.CheckRead(resource)
    if not allowed.ok then return allowed end
    return Ok(Organizations.Copy(catalog))
end
-- Pure internal validation only: neither UUID shape nor this catalog proves a
-- holder exists. Durable holder resolution is required before any future write.
function OrganizationInterests.ValidateGrant(request)
    if type(request)~='table' then return Err('invalid_input','Interest request required.') end
    local fields={organizationId=true,expectedRevision=true,requestId=true,reasonCode=true,
        interestType=true,holderType=true,holderId=true}
    for field in pairs(request) do
        if not fields[field] then return Err('invalid_input','Unexpected interest field.') end
    end
    if not Organizations.Uuid(request.organizationId) or not Organizations.Uuid(request.holderId)
        or not Organizations.Integer(request.expectedRevision,1,9007199254740990)
        or type(request.requestId)~='string' or #request.requestId>128
        or not request.requestId:match('^[A-Za-z0-9][A-Za-z0-9._:%-]*$')
        or type(request.reasonCode)~='string' or #request.reasonCode>64
        or not request.reasonCode:match('^[a-z][a-z0-9._:%-]*$') then
        return Err('invalid_input','UUIDs, integer revision, stable request ID and bounded reason required.')
    end
    local permitted=false
    for _,definition in ipairs(catalog) do
        if definition.key==request.interestType then
            for _,holderType in ipairs(definition.holderTypes) do
                if holderType==request.holderType then permitted=true end
            end
        end
    end
    if not permitted then return Err('invalid_input','Interest and holder types are incompatible.') end
    if request.holderType=='organization' and request.organizationId:lower()==request.holderId:lower() then
        return Err('invalid_input','Organization cannot hold its own controlling interest.')
    end
    local parts={request.organizationId:lower(),tostring(request.expectedRevision),request.interestType,
        request.holderType,request.holderId:lower(),request.reasonCode}
    for index,value in ipairs(parts) do parts[index]=tostring(#value)..':'..value end
    return Ok(table.concat(parts))
end
exports('ListOrganizationInterestTypes',function()
    local called,result=xpcall(function() return OrganizationInterests.Types(GetInvokingResource()) end,debug.traceback)
    if not called then return Err('internal_error','Interest catalog read failed.') end
    return result
end)

function OrganizationInterests.Change(request,resource,operation)
    if Config.Access.trustedMutators[resource or '']~=true then return Err('authorization_denied','Caller is not a trusted interest mutator.') end
    local allowed=Organizations.CheckRead(resource)
    if not allowed.ok then return allowed end
    if operation~='grant' and operation~='revoke' then return Err('invalid_input','Interest operation required.') end
    local valid=OrganizationInterests.ValidateGrant(request)
    if not valid.ok then return valid end
    request=Organizations.Copy(request)
    request.organizationId=request.organizationId:lower();request.holderId=request.holderId:lower()
    local fingerprint=operation..':'..valid.value
    if Config.Authorization.enabled then
        local decision=exports['feather-core']:Authorize(Config.Authorization.interestAction,{
            correlationId=request.requestId,subject={resource=resource,organizationId=request.organizationId,operation='interest_'..operation}})
        if type(decision)~='table' or not decision.ok or type(decision.value)~='table' or decision.value.allowed~=true then
            return Err('authorization_denied','Interest policy denied.')
        end
    end
    local result
    local called,committed=pcall(MySQL.startTransaction,function(query)
        local executed,outcome=xpcall(function()
            -- Same ordering as hierarchy writers: guard, receipt, then sorted
            -- organization rows. Holder/target lifecycle checks share row locks.
            local guard=query('SELECT `id` FROM `feather_organization_hierarchy_guard` WHERE `id`=1 FOR UPDATE') or {}
            if not guard[1] then return Err('invalid_persistence','Organization graph guard missing.') end
            query([[INSERT IGNORE INTO `feather_organization_interest_receipts`
                (`source_resource`,`request_id`,`request_fingerprint`) VALUES (?,?,?)]],{resource,request.requestId,fingerprint})
            local receipts=query([[SELECT `request_fingerprint`,`result_json` FROM `feather_organization_interest_receipts`
                WHERE `source_resource`=? AND `request_id`=? FOR UPDATE]],{resource,request.requestId}) or {}
            local receipt=receipts[1]
            if not receipt then return Err('internal_error','Could not reserve interest receipt.') end
            if receipt.request_fingerprint~=fingerprint then return Err('idempotency_conflict','Request ID is bound to another interest operation.') end
            local nodes=query([[SELECT `organization_id`,`created_by_resource`,`status`,`revision` FROM `feather_organizations`
                WHERE `organization_id` IN (?,?) ORDER BY `organization_id` FOR UPDATE]],
                {request.organizationId,request.holderType=='organization' and request.holderId or request.organizationId}) or {}
            local target,holder
            for _,row in ipairs(nodes) do
                if row.organization_id==request.organizationId then target=row end
                if row.organization_id==request.holderId then holder=row end
            end
            if not target then return Err('organization_not_found','Target organization not found.') end
            if target.created_by_resource~=resource and Config.Access.privilegedMutators[resource]~=true then
                return Err('authorization_denied','Caller does not own the target organization.')
            end
            local status=operation=='grant' and 'active' or 'revoked'
            if receipt.result_json then
                local decoded,value=pcall(json.decode,receipt.result_json)
                if not decoded or type(value)~='table' or not Organizations.Uuid(value.interestId)
                    or value.organizationId~=request.organizationId or value.holderId~=request.holderId
                    or value.holderType~=request.holderType or value.interestType~=request.interestType
                    or value.status~=status or value.revision~=request.expectedRevision+1 then
                    return Err('invalid_persistence','Stored interest receipt is invalid.')
                end
                value.replayed=true;return Ok(value)
            end
            local events=query('SELECT `event_id` FROM `feather_organization_events` WHERE `source_resource`=? AND `request_id`=?',
                {resource,request.requestId}) or {}
            if #events>0 then return Err('idempotency_conflict','Request ID belongs to another organization operation.') end
            if tonumber(target.revision)~=request.expectedRevision then return Err('revision_conflict','Organization revision changed.') end
            if target.status=='dissolved' or (operation=='grant' and target.status~='pending' and target.status~='active' and target.status~='suspended') then
                return Err('organization_inactive','Target lifecycle blocks this interest operation.')
            end
            if operation=='grant' then
                if request.holderType=='organization' then
                    if not holder then return Err('holder_not_found','Organization holder not found.') end
                    if holder.status~='active' then return Err('holder_inactive','Organization holder must be active.') end
                else
                    local resolved=OrganizationInterests.ResolveHolder({holderType=request.holderType,holderId=request.holderId},resource)
                    if not resolved.ok then return resolved end
                end
            end
            local interests=query([[SELECT `interest_id`,`status` FROM `feather_organization_interests`
                WHERE `organization_id`=? AND `interest_type`=? AND `holder_type`=? AND `holder_id`=? FOR UPDATE]],
                {request.organizationId,request.interestType,request.holderType,request.holderId}) or {}
            local interest=interests[1]
            if operation=='revoke' and not interest then return Err('interest_not_found','Interest not found.') end
            if interest and interest.status==status then return Err('no_change','Interest is already in the requested state.') end
            local id=interest and interest.interest_id
            if not id then
                local ids=query('SELECT UUID() AS id') or {};id=ids[1] and ids[1].id
                if not Organizations.Uuid(id) then return Err('invalid_persistence','Interest UUID unavailable.') end
                query([[INSERT INTO `feather_organization_interests`
                    (`interest_id`,`organization_id`,`interest_type`,`holder_type`,`holder_id`,`status`,`revision`)
                    VALUES (?,?,?,?,?,?,?)]],{id,request.organizationId,request.interestType,request.holderType,request.holderId,status,request.expectedRevision+1})
            else
                query('UPDATE `feather_organization_interests` SET `status`=?,`revision`=? WHERE `interest_id`=?',
                    {status,request.expectedRevision+1,id})
            end
            query('UPDATE `feather_organizations` SET `revision`=`revision`+1 WHERE `organization_id`=? AND `revision`=?',
                {request.organizationId,request.expectedRevision})
            OrganizationEvents.Record(query,request.organizationId,'organization.interest_'..(operation=='grant' and 'granted' or 'revoked'),
                resource,request.requestId,request.reasonCode,request.expectedRevision+1,{interestId=id,interestType=request.interestType,interestStatus=status})
            local value={interestId=id,organizationId=request.organizationId,holderType=request.holderType,holderId=request.holderId,
                interestType=request.interestType,status=status,revision=request.expectedRevision+1,replayed=false}
            query('UPDATE `feather_organization_interest_receipts` SET `result_json`=? WHERE `source_resource`=? AND `request_id`=?',
                {json.encode(value),resource,request.requestId})
            return Ok(value)
        end,debug.traceback)
        if not executed then print('[feather-organizations] interest transaction failed: '..tostring(outcome));result=Err('internal_error','Interest transaction failed.');return false end
        result=outcome;return outcome.ok==true
    end)
    if not called or (result and result.ok and committed~=true) then return Err('transaction_failed','Interest commit not confirmed. Retry the same request ID.') end
    return result or Err('transaction_failed','Interest transaction did not complete.')
end
local function InterestBoundary(request,operation)
    local called,result=xpcall(function() return OrganizationInterests.Change(request,GetInvokingResource(),operation) end,debug.traceback)
    if not called then return Err('internal_error','Interest operation failed.') end
    return result
end
exports('GrantOrganizationInterest',function(request) return InterestBoundary(request,'grant') end)
exports('RevokeOrganizationInterest',function(request) return InterestBoundary(request,'revoke') end)

local interestLiveRunning=false
RegisterCommand('OrganizationsInterestLiveTest',function(source,args)
    if source~=0 or not Config.DevMode then return end
    if interestLiveRunning then print('[OrganizationsInterestLiveTest] FAIL test already running');return end
    interestLiveRunning=true
    local called,reason=xpcall(function()
        assert(#args==2 and type(args[1])=='string' and #args[1]<=100 and Organizations.Uuid(args[2]),
            'Use <stable requestId, maximum 100 bytes> <character UUID>')
        assert(Organizations.AwaitReady(0).ok,'Service not ready')
        local owner=GetCurrentResourceName()
        local function Require(result)
            assert(result.ok,tostring(result.code)..': '..tostring(result.message));return result.value
        end
        local created=Require(OrganizationIdentity.Create({requestId=args[1]..':create',organizationType='business',
            organizationKey='org_interest_test',legalName='Organization Interest Test Company',displayName='Interest Test',
            reasonCode='development.interest_test'},owner))
        local id=created.organizationId
        local grant={organizationId=id,expectedRevision=1,requestId=args[1]..':grant',reasonCode='development.interest_test',
            interestType='owner',holderType='character',holderId=args[2]:lower()}
        local first=Require(OrganizationInterests.Change(grant,owner,'grant'))
        local revoke=Organizations.Copy(grant);revoke.expectedRevision=2;revoke.requestId=args[1]..':revoke'
        local revoked=Require(OrganizationInterests.Change(revoke,owner,'revoke'))
        local regrant=Organizations.Copy(grant);regrant.expectedRevision=3;regrant.requestId=args[1]..':regrant'
        local restored=Require(OrganizationInterests.Change(regrant,owner,'grant'))
        local replay=Require(OrganizationInterests.Change(grant,owner,'grant'))
        local revokeReplay=Require(OrganizationInterests.Change(revoke,owner,'revoke'))
        assert(first.interestId==revoked.interestId and first.interestId==restored.interestId,'Interest UUID changed')
        assert(replay.replayed and replay.revision==2 and revokeReplay.replayed and revokeReplay.status=='revoked','Original receipts did not replay')
        local stale=Organizations.Copy(grant);stale.requestId=args[1]..':stale'
        local staleResult=OrganizationInterests.Change(stale,owner,'grant')
        assert(not staleResult.ok and staleResult.code=='revision_conflict','Stale change accepted')
        local unchanged=Organizations.Copy(grant);unchanged.expectedRevision=4;unchanged.requestId=args[1]..':noop'
        local noChange=OrganizationInterests.Change(unchanged,owner,'grant')
        assert(not noChange.ok and noChange.code=='no_change','Duplicate active grant accepted')
        local mismatch=Organizations.Copy(grant);mismatch.interestType='founder'
        local mismatchResult=OrganizationInterests.Change(mismatch,owner,'grant')
        assert(not mismatchResult.ok and mismatchResult.code=='idempotency_conflict','Payload mismatch accepted')
        local missing=Organizations.Copy(grant);missing.expectedRevision=4;missing.requestId=args[1]..':missing'
        missing.holderId='00000000-0000-0000-0000-000000000000'
        local missingResult=OrganizationInterests.Change(missing,owner,'grant')
        assert(not missingResult.ok and missingResult.code=='holder_not_found','Missing holder accepted')
        local after=Require(OrganizationIdentity.Get({organizationId=id},owner))
        assert(after.revision==4 and after.status=='pending','Replay/rejection altered organization')
        local row=MySQL.single.await('SELECT `interest_id`,`status`,`revision` FROM `feather_organization_interests` WHERE `organization_id`=?',{id})
        assert(row and row.interest_id==first.interestId and row.status=='active' and tonumber(row.revision)==4,'Interest persistence inconsistent')
        local counts=MySQL.single.await([[SELECT
            (SELECT COUNT(*) FROM `feather_organization_interests` WHERE `organization_id`=?) AS interests,
            (SELECT COUNT(*) FROM `feather_organization_events` WHERE `organization_id`=?) AS events,
            (SELECT COUNT(*) FROM `feather_organization_outbox` o JOIN `feather_organization_events` e ON e.event_id=o.event_id WHERE e.organization_id=?) AS outbox,
            (SELECT COUNT(*) FROM `feather_organization_interest_receipts` WHERE source_resource=? AND request_id IN (?,?,?)) AS receipts,
            (SELECT COUNT(*) FROM `feather_organization_interest_receipts` WHERE source_resource=? AND request_id IN (?,?,?)) AS rejected_receipts]],
            {id,id,id,owner,grant.requestId,revoke.requestId,regrant.requestId,owner,stale.requestId,unchanged.requestId,missing.requestId})
        assert(tonumber(counts.interests)==1 and tonumber(counts.events)==4 and tonumber(counts.outbox)==4
            and tonumber(counts.receipts)==3 and tonumber(counts.rejected_receipts)==0,'Atomic record counts invalid')
        local rows=MySQL.query.await([[SELECT o.payload_json FROM `feather_organization_outbox` o
            JOIN `feather_organization_events` e ON e.event_id=o.event_id
            WHERE e.organization_id=? AND e.event_type IN ('organization.interest_granted','organization.interest_revoked')]],{id}) or {}
        assert(#rows==3,'Interest events missing')
        for _,event in ipairs(rows) do
            local payload=json.decode(event.payload_json)
            assert(payload.interestId==first.interestId and payload.holderId==nil and payload.holderType==nil
                and payload.legalName==nil and payload.displayName==nil,'Event identity/privacy invalid')
        end
        print(('[OrganizationsInterestLiveTest] PASS id=%s interestId=%s revision=4 state=active firstReplayed=%s originalReceipts=true stableIdentity=true staleRejected=true mismatchRejected=true missingRejected=true events=4 outbox=4 rolledBack=true privateFieldsExcluded=true'):format(
            id,first.interestId,tostring(first.replayed)))
    end,debug.traceback)
    interestLiveRunning=false
    if not called then print('[OrganizationsInterestLiveTest] FAIL '..tostring(reason)) end
end,true)

RegisterCommand('OrganizationsInterestContractSmokeTest',function(source)
    if source~=0 then return end
    local called,reason=xpcall(function()
        assert(Organizations.AwaitReady(0).ok,'Service not ready')
        local owner=GetCurrentResourceName()
        local tests={}
        local function Check(label,good) tests[#tests+1]={label,good==true} end
        local definitions=OrganizationInterests.Types(owner)
        Check('bounded type catalog',definitions.ok and #definitions.value==3)
        definitions.value[1].key='tampered'
        Check('catalog isolated',OrganizationInterests.Types(owner).value[1].key=='founder')
        local denied=OrganizationInterests.Types('untrusted-smoke-caller')
        Check('untrusted catalog rejected',not denied.ok and denied.code=='authorization_denied')
        local request={organizationId='00000000-0000-0000-0000-000000000001',
            holderId='00000000-0000-0000-0000-000000000002',holderType='character',interestType='owner',
            expectedRevision=1,requestId='interest-contract-001',reasonCode='development.interest_test'}
        Check('valid character owner',OrganizationInterests.ValidateGrant(request).ok)
        local organizational=Organizations.Copy(request);organizational.holderType='organization';organizational.interestType='controlling_organization'
        Check('valid organization control',OrganizationInterests.ValidateGrant(organizational).ok)
        for _,case in ipairs({{'interestType','employee'},{'holderType','player'},{'holderId','bad'},
            {'expectedRevision',1.5},{'requestId','bad id'},{'sourceResource',owner},{'shares',50}}) do
            local invalid=Organizations.Copy(request);invalid[case[1]]=case[2]
            Check('rejected '..case[1],not OrganizationInterests.ValidateGrant(invalid).ok)
        end
        local founder=Organizations.Copy(organizational);founder.interestType='founder'
        Check('founder holder constrained',not OrganizationInterests.ValidateGrant(founder).ok)
        local self=Organizations.Copy(organizational);self.holderId=self.organizationId
        Check('self control rejected',not OrganizationInterests.ValidateGrant(self).ok)
        local changed=Organizations.Copy(request);changed.holderId='00000000-0000-0000-0000-000000000003'
        Check('holder payload binding',OrganizationInterests.ValidateGrant(request).value~=OrganizationInterests.ValidateGrant(changed).value)
        Check('writes available',Organizations.GetCapabilities().value.features.controllingInterests==1)
        local deniedGrant=OrganizationInterests.Change(request,'untrusted-smoke-caller','grant')
        Check('untrusted grant rejected',not deniedGrant.ok and deniedGrant.code=='authorization_denied')
        local deniedRevoke=OrganizationInterests.Change(request,'untrusted-smoke-caller','revoke')
        Check('untrusted revoke rejected',not deniedRevoke.ok and deniedRevoke.code=='authorization_denied')
        local passed=0
        for _,test in ipairs(tests) do
            if test[2] then passed=passed+1 end
            print(('[OrganizationsInterestContractSmokeTest] %-29s %s'):format(test[1],test[2] and 'PASS' or 'FAIL'))
        end
        print(('[OrganizationsInterestContractSmokeTest] done %d/%d passed (no interests created)'):format(passed,#tests))
    end,debug.traceback)
    if not called then print('[OrganizationsInterestContractSmokeTest] FAIL '..tostring(reason)) end
end,true)

RegisterCommand('OrganizationsHolderContractSmokeTest',function(source)
    if source~=0 then return end
    local called,reason=xpcall(function()
        assert(Organizations.AwaitReady(0).ok,'Service not ready')
        local tests={}
        local function Check(label,good) tests[#tests+1]={label,good==true} end
        local id='00000000-0000-0000-0000-000000000001'
        Check('character provider ready',OrganizationInterests.CharacterProvider().ok)
        Check('Cfx reference callable',IsCallable({__cfx_functionReference='test'}))
        Check('plain table not callable',not IsCallable({}))
        local valid=OrganizationInterests.CharacterSnapshot(Ok({characterId=id,status='active',firstName='Private',accountId='Private'}),id)
        Check('private fields excluded',valid.ok and valid.value.firstName==nil and valid.value.accountId==nil)
        local missing=OrganizationInterests.CharacterSnapshot(Err('not_found','Missing'),id)
        Check('missing holder rejected',not missing.ok and missing.code=='holder_not_found')
        local inactive=OrganizationInterests.CharacterSnapshot(Ok({characterId=id,status='deleted'}),id)
        Check('inactive holder rejected',not inactive.ok and inactive.code=='holder_inactive')
        Check('wrong identity rejected',not OrganizationInterests.CharacterSnapshot(Ok({characterId='00000000-0000-0000-0000-000000000002',status='active'}),id).ok)
        Check('bad result rejected',not OrganizationInterests.CharacterSnapshot(true,id).ok)
        Check('invalid UUID rejected',not OrganizationInterests.ResolveHolder({holderType='character',holderId='bad'},GetCurrentResourceName()).ok)
        local denied=OrganizationInterests.ResolveHolder({holderType='character',holderId=id},'untrusted-smoke-caller')
        Check('untrusted lookup rejected',not denied.ok and denied.code=='authorization_denied')
        local passed=0
        for _,test in ipairs(tests) do
            if test[2] then passed=passed+1 end
            print(('[OrganizationsHolderContractSmokeTest] %-29s %s'):format(test[1],test[2] and 'PASS' or 'FAIL'))
        end
        print(('[OrganizationsHolderContractSmokeTest] done %d/%d passed (read-only)'):format(passed,#tests))
    end,debug.traceback)
    if not called then print('[OrganizationsHolderContractSmokeTest] FAIL '..tostring(reason)) end
end,true)

RegisterCommand('OrganizationsHolderLiveTest',function(source,args)
    if source~=0 or not Config.DevMode then return end
    local called,reason=xpcall(function()
        assert(#args==2,'Use character|organization <holder UUID>; no player source required')
        local result=OrganizationInterests.ResolveHolder({holderType=args[1],holderId=args[2]},GetCurrentResourceName())
        assert(result.ok,tostring(result.code)..': '..tostring(result.message))
        assert(result.value.holderId==args[2]:lower() and result.value.holderType==args[1],'Holder identity mismatch')
        for field in pairs(result.value) do assert(field=='holderId' or field=='holderType' or field=='status','Unexpected private field') end
        print(('[OrganizationsHolderLiveTest] PASS type=%s id=%s active=true privateFieldsExcluded=true sessionNotRequired=true (read-only)'):format(result.value.holderType,result.value.holderId))
    end,debug.traceback)
    if not called then print('[OrganizationsHolderLiveTest] FAIL '..tostring(reason)) end
end,true)
