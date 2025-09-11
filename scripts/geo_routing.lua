-- PowerDNS Lua script for geographic routing with health checks
-- This script handles DNS queries for cdn-geo.runonflux.io

-- Server configuration with IP addresses and geographic locations
servers = {
    {
        name = "cdn-6.runonflux.io",
        ip = "107.152.47.137",
        location = "us-west",
        continent = "NA",
        lat = 37.7749,
        lon = -122.4194
    },
    {
        name = "cdn-1.runonflux.io",
        ip = "5.39.57.50",
        location = "eu-west",
        continent = "EU",
        lat = 51.0344,
        lon = 2.3768
    },
    {
        name = "cdn-12.runonflux.io",
        ip = "114.29.237.116",
        location = "asia-east",
        continent = "AS",
        lat = 22.3193,
        lon = 114.1694
    }
}

-- Track server recovery times (servers that were down and came back up)
-- Format: recovery_times[ip] = timestamp when server came back online
recovery_times = {}

-- Function to get all server IPs
function getAllServerIPs()
    local ips = {}
    for _, server in ipairs(servers) do
        table.insert(ips, server.ip)
    end
    return ips
end

-- Function to check if a server has been up for at least 5 minutes after recovery
function isServerRecovered(ip)
    local recovery_time = recovery_times[ip]
    if recovery_time == nil then
        -- Server hasn't been marked as recovering, so it's available
        return true
    end

    -- Check if 5 minutes (300 seconds) have passed since recovery
    local current_time = os.time()
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

    -- Health check: port 443 (HTTPS), 15 second interval, 3 failures = 45 seconds to detect failure
    -- This returns only the IPs that are currently responding
    local available_ips = ifportup(443, all_ips, {
        timeout = 2000,        -- 2 seconds connection timeout in milliseconds
        minimumFailures = 3,   -- 3 consecutive failures before marking as down
        interval = 15,         -- Check every 15 seconds (balanced approach)
        selector = 'all'       -- Return ALL healthy servers, not just one
    })

    -- Filter out servers that are still in recovery period
    local healthy_ips = {}
    for _, ip in ipairs(available_ips) do
        if isServerRecovered(ip) then
            table.insert(healthy_ips, ip)
        end
    end

    -- Track newly recovered servers
    for _, ip in ipairs(available_ips) do
        local was_down = true
        for _, healthy_ip in ipairs(healthy_ips) do
            if ip == healthy_ip then
                was_down = false
                break
            end
        end

        -- If server is available but not in healthy list, it's recovering
        if was_down and recovery_times[ip] == nil then
            recovery_times[ip] = os.time()
        end
    end

    -- If no healthy servers are available, use all available servers as fallback
    if #healthy_ips == 0 then
        healthy_ips = available_ips
    end

    -- If still no servers available, return all servers (last resort)
    if #healthy_ips == 0 then
        return all_ips
    end

    -- Use pickclosest to select geographically nearest server
    -- This function uses the GeoIP data of the requesting client
    return pickclosest(healthy_ips)
end

-- Alternative function for weighted geographic routing
function geoRouteWeighted()
    local all_ips = getAllServerIPs()

    -- Health check with same parameters as above
    local available_ips = ifportup(443, all_ips, {
        timeout = 2000,
        minimumFailures = 3,
        interval = 15,         -- Check every 15 seconds
        selector = 'all'       -- Return ALL healthy servers, not just one
    })

    -- Filter recovered servers
    local healthy_ips = {}
    for _, ip in ipairs(available_ips) do
        if isServerRecovered(ip) then
            table.insert(healthy_ips, ip)
        end
    end

    -- Track recovery
    for _, ip in ipairs(available_ips) do
        local was_down = true
        for _, healthy_ip in ipairs(healthy_ips) do
            if ip == healthy_ip then
                was_down = false
                break
            end
        end
        if was_down and recovery_times[ip] == nil then
            recovery_times[ip] = os.time()
        end
    end

    -- Fallback logic
    if #healthy_ips == 0 then
        healthy_ips = available_ips
    end
    if #healthy_ips == 0 then
        return all_ips
    end

    -- Return weighted selection based on geographic distribution
    -- This can be customized based on traffic patterns
    return pickwrandom(healthy_ips)
end

-- Function for A record queries specifically
function geoRouteA()
    return geoRoute()
end

-- Function for AAAA record queries (IPv6) - returns empty for now
function geoRouteAAAA()
    return {}
end

-- Function to get server status (for monitoring/debugging)
function getServerStatus()
    local all_ips = getAllServerIPs()
    local available_ips = ifportup(443, all_ips, {
        timeout = 2000,
        minimumFailures = 3,
        interval = 15,         -- Check every 15 seconds
        selector = 'all'       -- Return ALL healthy servers, not just one
    })

    local status = {}
    for _, server in ipairs(servers) do
        local is_available = false
        for _, available_ip in ipairs(available_ips) do
            if server.ip == available_ip then
                is_available = true
                break
            end
        end

        local is_healthy = is_available and isServerRecovered(server.ip)

        table.insert(status, {
            name = server.name,
            ip = server.ip,
            location = server.location,
            available = is_available,
            healthy = is_healthy,
            recovering = is_available and not is_healthy
        })
    end

    return status
end
