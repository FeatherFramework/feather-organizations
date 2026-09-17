Config = {
    Contract = 1,
    RequiredCoreContract = 1,
    ReadinessTimeoutMs = 30000,
    DevMode = true,
    Authorization = { enabled = false, createAction = 'organizations.organization.create',
        updateAction = 'organizations.organization.update',
        suspendAction = 'organizations.organization.suspend',
        dissolveAction = 'organizations.organization.dissolve' },
    Access = {
        trustedCreators = { ['feather-organizations'] = true, ['feather-admin'] = true },
        trustedMutators = { ['feather-organizations'] = true, ['feather-admin'] = true },
        privilegedMutators = { ['feather-admin'] = true },
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
end
