Config = {
    Contract = 1,
    RequiredCoreContract = 1,
    ReadinessTimeoutMs = 30000,
    DevMode = true,
    Authorization = { enabled = false, createAction = 'organizations.organization.create' },
    Access = {
        trustedCreators = { ['feather-organizations'] = true, ['feather-admin'] = true },
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
