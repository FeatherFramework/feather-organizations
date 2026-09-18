Config = {
    Contract = 1,
    RequiredCoreContract = 1,
    ReadinessTimeoutMs = 30000,
    DevMode = true,
    Outbox = { pollIntervalMs = 1000, retryDelaySeconds = 5, batchSize = 20 },
    Authorization = { enabled = true, createAction = 'organizations.organization.create',
        updateAction = 'organizations.organization.update',
        suspendAction = 'organizations.organization.suspend',
        dissolveAction = 'organizations.organization.dissolve',
        hierarchyAction = 'organizations.relationship.manage', interestAction = 'organizations.interest.manage' },
    Access = {
        trustedCreators = { ['feather-organizations'] = true, ['feather-admin'] = true, ['feather-shops'] = true },
        trustedMutators = { ['feather-organizations'] = true, ['feather-admin'] = true, ['feather-shops'] = true },
        privilegedMutators = { ['feather-admin'] = true },
        trustedAuditors = { ['feather-organizations'] = true, ['feather-admin'] = true, ['feather-shops'] = true },
        privilegedAuditors = { ['feather-admin'] = true },
        trustedReaders = {
            ['feather-organizations'] = true,
            ['feather-admin'] = true,
            ['feather-economy'] = true,
            ['feather-shops'] = true
        }
    },
    -- Stable keys are immutable classification, not permissions or gameplay.
    Types = {
        { key = 'business', label = 'Business' },
        { key = 'government', label = 'Government' },
        { key = 'government_agency', label = 'Government Agency' }
    }
}

-- Optional acceptance fixture only. Never start it or grant it trust in production.
if Config.DevMode then
    Config.Access.trustedReaders['feather-organizations-tests'] = true
    Config.Access.trustedCreators['feather-organizations-tests'] = true
    Config.Access.trustedMutators['feather-organizations-tests'] = true
    Config.Access.trustedAuditors['feather-organizations-tests'] = true
end
