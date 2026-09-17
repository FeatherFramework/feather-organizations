local running = false
RegisterCommand('OrganizationsConcurrencyTest', function(source,args)
    if source ~= 0 or not Config.DevMode then return end
    if running then print('[OrganizationsConcurrencyTest] FAIL test already running'); return end
    local base = args[1]
    if #args ~= 1 or type(base) ~= 'string' or #base > 100
        or not base:match('^[A-Za-z0-9][A-Za-z0-9._:%-]*$') then
        print('[OrganizationsConcurrencyTest] FAIL use <stable requestId up to 100 characters>'); return
    end
    running = true
    CreateThread(function()
        local called, errorMessage = xpcall(function()
            local owner = GetCurrentResourceName()
            print('[OrganizationsConcurrencyTest] started')
            local created = OrganizationIdentity.Create({ requestId=base .. ':create',organizationType='business',
                organizationKey='org_concurrency_test',legalName='Organization Concurrency Test Company',
                displayName='Organization Concurrency Test',reasonCode='development.concurrency_test' },owner)
            if not created.ok then print('[OrganizationsConcurrencyTest] FAIL create code=' .. created.code); return end
            local id = created.value.organizationId
            local requests = {
                { organizationId=id,expectedRevision=1,status='active',requestId=base .. ':a',reasonCode='development.concurrency_test' },
                { organizationId=id,expectedRevision=1,status='dissolving',requestId=base .. ':b',reasonCode='development.concurrency_test' }
            }
            local outcomes, finished = {}, 0
            -- Do not await promises or use # on an asynchronously populated array.
            -- Each completion advances an explicit counter, with a bounded watchdog.
            for index=1,2 do
                local slot = index
                CreateThread(function()
                    local ok,result = xpcall(function() return OrganizationLifecycle.Change(requests[slot],owner) end,debug.traceback)
                    outcomes[slot] = ok and result or Organizations.Err('internal_error','Concurrency child failed.')
                    finished = finished+1
                    print(('[OrganizationsConcurrencyTest] contender=%d ok=%s code=%s'):format(
                        slot,tostring(outcomes[slot].ok),tostring(outcomes[slot].code)))
                end)
            end
            local started = GetGameTimer()
            while finished < 2 and GetGameTimer()-started < 30000 do Wait(50) end
            if finished < 2 then
                print('[OrganizationsConcurrencyTest] FAIL timed out; retain request ID and inspect state before retrying'); return
            end
            local success,stale,winner,loser = 0,0,nil,nil
            for index=1,2 do
                if outcomes[index].ok then success=success+1;winner=index
                elseif outcomes[index].code=='revision_conflict' then stale=stale+1;loser=index end
            end
            local replay = winner and OrganizationLifecycle.Change(requests[winner],owner)
            local current = OrganizationIdentity.Get({organizationId=id},owner)
            local counts = MySQL.single.await([[SELECT
                (SELECT COUNT(*) FROM `feather_organization_events` WHERE `organization_id`=?) AS events,
                (SELECT COUNT(*) FROM `feather_organization_lifecycle_receipts`
                    WHERE `source_resource`=? AND `request_id` IN (?,?)) AS receipts]],
                {id,owner,requests[1].requestId,requests[2].requestId})
            local good = success==1 and stale==1 and replay and replay.ok and replay.value.replayed==true
                and current.ok and current.value.revision==2 and current.value.status==requests[winner].status
                and counts and tonumber(counts.events)==2 and tonumber(counts.receipts)==1
            print(('[OrganizationsConcurrencyTest] %s id=%s committed=%d stale=%d revision=%s events=%s receipts=%s winnerReplayed=%s'):format(
                good and 'PASS' or 'FAIL',id,success,stale,tostring(current.ok and current.value.revision),
                tostring(counts and counts.events),tostring(counts and counts.receipts),tostring(replay and replay.ok and replay.value.replayed)))
        end,debug.traceback)
        running=false
        if not called then print('[OrganizationsConcurrencyTest] FAIL ' .. tostring(errorMessage)) end
    end)
end,true)
