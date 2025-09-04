-- PowerDNS Lua script for app routing
-- This script replicates the logic from the Python pipe backend
-- Routes subdomains based on first character to specific load balancers

-- Load balancer mappings for production environment
local production_mappings = {
    -- Characters 0-9, a-g -> fdm-lb-1-1.runonflux.io
    ['0'] = "fdm-lb-1-1.runonflux.io",
    ['1'] = "fdm-lb-1-1.runonflux.io", 
    ['2'] = "fdm-lb-1-1.runonflux.io",
    ['3'] = "fdm-lb-1-1.runonflux.io",
    ['4'] = "fdm-lb-1-1.runonflux.io",
    ['5'] = "fdm-lb-1-1.runonflux.io",
    ['6'] = "fdm-lb-1-1.runonflux.io",
    ['7'] = "fdm-lb-1-1.runonflux.io",
    ['8'] = "fdm-lb-1-1.runonflux.io",
    ['9'] = "fdm-lb-1-1.runonflux.io",
    ['a'] = "fdm-lb-1-1.runonflux.io",
    ['b'] = "fdm-lb-1-1.runonflux.io",
    ['c'] = "fdm-lb-1-1.runonflux.io",
    ['d'] = "fdm-lb-1-1.runonflux.io",
    ['e'] = "fdm-lb-1-1.runonflux.io",
    ['f'] = "fdm-lb-1-1.runonflux.io",
    ['g'] = "fdm-lb-1-1.runonflux.io",
    
    -- Characters h-n -> fdm-lb-1-2.runonflux.io
    ['h'] = "fdm-lb-1-2.runonflux.io",
    ['i'] = "fdm-lb-1-2.runonflux.io",
    ['j'] = "fdm-lb-1-2.runonflux.io",
    ['k'] = "fdm-lb-1-2.runonflux.io",
    ['l'] = "fdm-lb-1-2.runonflux.io",
    ['m'] = "fdm-lb-1-2.runonflux.io",
    ['n'] = "fdm-lb-1-2.runonflux.io",
    
    -- Characters o-u -> fdm-lb-1-3.runonflux.io
    ['o'] = "fdm-lb-1-3.runonflux.io",
    ['p'] = "fdm-lb-1-3.runonflux.io",
    ['q'] = "fdm-lb-1-3.runonflux.io",
    ['r'] = "fdm-lb-1-3.runonflux.io",
    ['s'] = "fdm-lb-1-3.runonflux.io",
    ['t'] = "fdm-lb-1-3.runonflux.io",
    ['u'] = "fdm-lb-1-3.runonflux.io",
    
    -- Characters v-z -> fdm-lb-1-4.runonflux.io
    ['v'] = "fdm-lb-1-4.runonflux.io",
    ['w'] = "fdm-lb-1-4.runonflux.io",
    ['x'] = "fdm-lb-1-4.runonflux.io",
    ['y'] = "fdm-lb-1-4.runonflux.io",
    ['z'] = "fdm-lb-1-4.runonflux.io"
}

-- Load balancer mappings for staging environment
local staging_mappings = {
    -- Characters 0-9, a-m -> fdm-lb-2-1.runonflux.io
    ['0'] = "fdm-lb-2-1.runonflux.io",
    ['1'] = "fdm-lb-2-1.runonflux.io",
    ['2'] = "fdm-lb-2-1.runonflux.io",
    ['3'] = "fdm-lb-2-1.runonflux.io",
    ['4'] = "fdm-lb-2-1.runonflux.io",
    ['5'] = "fdm-lb-2-1.runonflux.io",
    ['6'] = "fdm-lb-2-1.runonflux.io",
    ['7'] = "fdm-lb-2-1.runonflux.io",
    ['8'] = "fdm-lb-2-1.runonflux.io",
    ['9'] = "fdm-lb-2-1.runonflux.io",
    ['a'] = "fdm-lb-2-1.runonflux.io",
    ['b'] = "fdm-lb-2-1.runonflux.io",
    ['c'] = "fdm-lb-2-1.runonflux.io",
    ['d'] = "fdm-lb-2-1.runonflux.io",
    ['e'] = "fdm-lb-2-1.runonflux.io",
    ['f'] = "fdm-lb-2-1.runonflux.io",
    ['g'] = "fdm-lb-2-1.runonflux.io",
    ['h'] = "fdm-lb-2-1.runonflux.io",
    ['i'] = "fdm-lb-2-1.runonflux.io",
    ['j'] = "fdm-lb-2-1.runonflux.io",
    ['k'] = "fdm-lb-2-1.runonflux.io",
    ['l'] = "fdm-lb-2-1.runonflux.io",
    ['m'] = "fdm-lb-2-1.runonflux.io",
    
    -- Characters n-z -> fdm-lb-2-2.runonflux.io
    ['n'] = "fdm-lb-2-2.runonflux.io",
    ['o'] = "fdm-lb-2-2.runonflux.io",
    ['p'] = "fdm-lb-2-2.runonflux.io",
    ['q'] = "fdm-lb-2-2.runonflux.io",
    ['r'] = "fdm-lb-2-2.runonflux.io",
    ['s'] = "fdm-lb-2-2.runonflux.io",
    ['t'] = "fdm-lb-2-2.runonflux.io",
    ['u'] = "fdm-lb-2-2.runonflux.io",
    ['v'] = "fdm-lb-2-2.runonflux.io",
    ['w'] = "fdm-lb-2-2.runonflux.io",
    ['x'] = "fdm-lb-2-2.runonflux.io",
    ['y'] = "fdm-lb-2-2.runonflux.io",
    ['z'] = "fdm-lb-2-2.runonflux.io"
}

-- Determine environment from zone name or use environment variable
function getEnvironment(qname)
    -- Check if this is app2.runonflux.io (staging) or app.runonflux.io (production)
    if string.find(qname, "app2%.runonflux%.io") then
        return "staging"
    else
        return "production"
    end
end

-- Main routing function for app subdomains
function appRoute(qname)
    -- Convert to lowercase for consistent matching
    local domain = string.lower(tostring(qname))
    
    -- Extract the first character of the subdomain
    -- For "myapp.app.runonflux.io", we want the 'm'
    local first_char = string.sub(domain, 1, 1)
    
    -- Determine environment
    local env = getEnvironment(domain)
    
    -- Select appropriate mapping table
    local mappings
    if env == "staging" then
        mappings = staging_mappings
    else
        mappings = production_mappings
    end
    
    -- Look up the load balancer for this character
    local target = mappings[first_char]
    
    if target then
        return target
    else
        -- Fallback for unexpected characters (should not happen in normal operation)
        if env == "staging" then
            return "fdm-lb-2-1.runonflux.io"  -- Default staging fallback
        else
            return "fdm-lb-1-1.runonflux.io"  -- Default production fallback
        end
    end
end

-- Function to generate CNAME records (matching pipe backend behavior)
function appRouteCname(qname)
    local result = appRoute(qname)
    if result then
        return result
    else
        return "fdm-lb-1-1.runonflux.io"  -- Default fallback
    end
end

-- Function for SOA queries (matching pipe backend behavior)  
function appRouteSoa(qname)
    -- Return SOA record exactly as production pipe backend provides
    local env = getEnvironment(qname)
    if env == "staging" then
        return "ns1.runonflux.io. st.runonflux.io. 2022040801 3600 600 86400 3600"
    else
        return "ns1.runonflux.io. st.runonflux.io. 2022040801 3600 600 86400 3600"
    end
end

-- Debug function to show routing decisions (can be queried via TXT record)
function appRouteDebug(qname)
    local domain = string.lower(tostring(qname))
    local first_char = string.sub(domain, 1, 1)
    local env = getEnvironment(domain)
    local target = appRoute(qname)
    
    return string.format("Domain: %s, First char: %s, Env: %s, Target: %s", 
                        domain, first_char, env, target)
end