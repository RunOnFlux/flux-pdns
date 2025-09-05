-- PowerDNS Lua script for geographic routing with health checks - DOCKER VERSION
-- This script handles DNS queries for cdn-geo.runonflux.io in Docker test environment

-- Server configuration with MOCK IP addresses for Docker testing
servers = {
    {
        name = "cdn-6-mock",
        ip = "172.25.0.50",
        location = "us-west",
        continent = "NA",
        lat = 37.7749,
        lon = -122.4194
    },
    {
        name = "cdn-1-mock",
        ip = "172.25.0.51",
        location = "eu-west",
        continent = "EU",
        lat = 48.8566,
        lon = 2.3522
    },
    {
        name = "cdn-4-mock",
        ip = "172.25.0.52",
        location = "asia-east",
        continent = "AS",
        lat = 22.3193,
        lon = 114.1694
    }
}

-- Track server recovery times (servers that were down and came back up)
-- Format: recovery_times[ip] = timestamp when server came back online
recovery_times = {}

-- Get all server IP addresses
function getAllServerIPs()
    local ips = {}
    for _, server in ipairs(servers) do
        table.insert(ips, server.ip)
    end
    return ips
end

-- Check if a server that was previously down has been up long enough to be considered recovered
function isServerRecovered(ip)
    local recovery_time = recovery_times[ip]

    -- If server was never down, it's always recovered
    if recovery_time == nil then
        return true
    end

    local current_time = os.time()

    -- Server needs to be up for 5 minutes (300 seconds) before being considered recovered
    if current_time - recovery_time >= 300 then
        -- Server has been up for 5 minutes, remove from recovery tracking
        recovery_times[ip] = nil
        return true
    end

    return false
end

-- Main geo-routing function called by PowerDNS
function geoRoute()
    local all_ips = getAllServerIPs()

    -- Health check: port 80 (HTTP), 2 second timeout, 3 failures threshold
    -- This returns only the IPs that are currently responding (mock servers)
    local available_ips = ifportup(80, all_ips, {
        timeout = 2000,        -- 2 seconds in milliseconds
        minimumFailures = 3,   -- 3 consecutive failures before marking as down
        interval = 2          -- Check every 2 seconds
    })

    -- Filter available IPs to only include those that have recovered (been up for 5+ minutes)
    local healthy_ips = {}
    for _, ip in ipairs(available_ips) do
        if isServerRecovered(ip) then
            table.insert(healthy_ips, ip)
        end
    end

    -- Track recovery times for newly available servers
    for _, ip in ipairs(all_ips) do
        local is_available = false
        for _, healthy_ip in ipairs(healthy_ips) do
            if ip == healthy_ip then
                is_available = true
                break
            end
        end

        -- If server is available but not in healthy list, it's recovering
        if not is_available then
            for _, avail_ip in ipairs(available_ips) do
                if ip == avail_ip and recovery_times[ip] == nil then
                    recovery_times[ip] = os.time()
                end
            end
        end
    end

    -- If no healthy servers are available, use all available servers as fallback
    if #healthy_ips == 0 then
        healthy_ips = available_ips
    end

    -- If still no servers available, return empty (will cause SERVFAIL)
    if #healthy_ips == 0 then
        return {}
    end

    -- Return the closest server based on geographic routing
    return pickclosest(healthy_ips)
end

-- Weighted random selection function for load balancing
function geoRouteWeighted()
    local all_ips = getAllServerIPs()

    -- Health check: port 80 (HTTP), 2 second timeout, 3 failures threshold
    local available_ips = ifportup(80, all_ips, {
        timeout = 2000,
        minimumFailures = 3,
        interval = 2
    })

    -- Filter for recovered servers
    local healthy_ips = {}
    for _, ip in ipairs(available_ips) do
        if isServerRecovered(ip) then
            table.insert(healthy_ips, ip)
        end
    end

    -- Track recovery times for newly available servers
    for _, ip in ipairs(all_ips) do
        local is_available = false
        for _, healthy_ip in ipairs(healthy_ips) do
            if ip == healthy_ip then
                is_available = true
                break
            end
        end

        if not is_available then
            for _, avail_ip in ipairs(available_ips) do
                if ip == avail_ip and recovery_times[ip] == nil then
                    recovery_times[ip] = os.time()
                end
            end
        end
    end

    if #healthy_ips == 0 then
        healthy_ips = available_ips
    end
    if #healthy_ips == 0 then
        return {}
    end

    -- Return weighted random server
    return pickwrandom(healthy_ips)
end

-- Debug function to get server status (for monitoring)
function getServerStatus()
    local all_ips = getAllServerIPs()
    local status = {}

    local available_ips = ifportup(80, all_ips, {
        timeout = 2000,
        minimumFailures = 3,
        interval = 2
    })

    for _, server in ipairs(servers) do
        local is_available = false
        for _, avail_ip in ipairs(available_ips) do
            if server.ip == avail_ip then
                is_available = true
                break
            end
        end

        local is_healthy = is_available and isServerRecovered(server.ip)

        status[server.name] = {
            ip = server.ip,
            location = server.location,
            available = is_available,
            healthy = is_healthy,
            recovering = is_available and not is_healthy
        }
    end

    return status
end
