Language = {}

Language.State = {
    AssignedLanguage = 'en',
    Locales = {},
    Loaded = false
}

local function normalizeLanguage(language)
    language = (language or 'en'):lower()

    if language == 'pt' or language == 'pt_br' then
        return 'pt-br'
    end

    if language == 'en-us' or language == 'en-gb' then
        return 'en'
    end

    return language
end

local function addCandidate(list, value)
    if not value or value == '' then return end

    for i = 1, #list do
        if list[i] == value then
            return
        end
    end

    list[#list + 1] = value
end

local function languageCandidates(language)
    local candidates = {}
    local raw = tostring(language or '')
    local trimmed = raw:match('^%s*(.-)%s*$') or ''
    local lower = trimmed:lower()
    local dashed = lower:gsub('_', '-')
    local underscored = lower:gsub('-', '_')
    local base = dashed:match('^([a-z]+)[-].*$') or underscored:match('^([a-z]+)[_].*$')

    addCandidate(candidates, trimmed)
    addCandidate(candidates, lower)
    addCandidate(candidates, dashed)
    addCandidate(candidates, underscored)
    addCandidate(candidates, normalizeLanguage(lower))
    addCandidate(candidates, base)
    addCandidate(candidates, 'en')

    return candidates
end

local function decodeLocaleFile(file)
    if not file then return nil end

    local ok, decoded = pcall(json.decode, file)
    if not ok or type(decoded) ~= 'table' then
        return nil
    end

    return decoded
end

local function getDesiredLanguage()
    if Config and Config.Language and Config.Language ~= '' then
        return normalizeLanguage(Config.Language)
    end

    return normalizeLanguage(GetConvar('locale', 'en'))
end

Language.SetLanguage = function(language)
    Language.State.AssignedLanguage = normalizeLanguage(language)
    return Language
end

Language.LoadLocales = function()
    local candidates = languageCandidates(Language.State.AssignedLanguage)

    for i = 1, #candidates do
        local file = LoadResourceFile(GetCurrentResourceName(), ('locales/%s.json'):format(candidates[i]))
        local decoded = decodeLocaleFile(file)

        if decoded then
            Language.State.Locales = decoded
            Language.State.Loaded = true
            return true
        end
    end

    Language.State.Locales = {}
    Language.State.Loaded = false
    return false
end

local function ensureLocalesLoaded()
    local desiredLanguage = getDesiredLanguage()

    if (not Language.State.Loaded) or Language.State.AssignedLanguage ~= desiredLanguage then
        Language.SetLanguage(desiredLanguage).LoadLocales()
    end
end

Language.Locale = function(key, ...)
    ensureLocalesLoaded()

    local text = Language.State.Locales[key]

    if not text then
        return key
    end

    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, text, ...)
        if ok then
            return formatted
        end
    end

    return text
end

function locale(key, ...)
    return Language.Locale(key, ...)
end
