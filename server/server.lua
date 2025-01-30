-- Fonction Debug (permet d'afficher des messages avec différents niveaux de gravité)
function Debug(message, level)
    local colors = {
        info = '^3',        -- couleur pour "info"
        success = '^2',     -- couleur pour "success"
        warning = '^8',     -- couleur pour "warning"
        error = '^1'        -- couleur pour "error"
    }
    
    level = level or 'info'  -- Si aucun niveau spécifié, utiliser 'info' par défaut
    local color = colors[level] or '^3'  -- Par défaut utiliser la couleur 'info' (jaune)
    
    print(string.format('%s[NEST-EVENT] %s^7', color, message))  -- Affiche le message coloré
end

-- Détection automatique du framework
local Framework = nil

-- Détection et initialisation du framework (avant toute utilisation de ESX ou QBCore)
if Config.Framework == 'ESX' then
    if ESX == nil then
        ESX = exports["es_extended"]:getSharedObject()  -- Initialisation d'ESX si nécessaire
    end
    
    -- Vérifier si ESX est bien initialisé
    if not ESX then
        Debug("ESX n'a pas pu être initialisé.", "error")
        return  -- Retourner si ESX est manquant
    end
elseif Config.Framework == 'QBCore' then
    if QBCore == nil then
        QBCore = exports['qb-core']:GetCoreObject()  -- Initialiser QBCore si nécessaire
    end

    -- Vérification de QBCore
    if not QBCore then
        Debug("QBCore n'a pas pu être initialisé.", "error")
        return  -- Retourner si QBCore est manquant
    end
end


local Spawn = exports[GetCurrentResourceName()]:GetSpawn()

-- Vérification que Config existe
if not Config then
    Config = {}
    Config.NestEvent = {
        Debug = true  -- Debug par défaut si config non chargée
    }
end

-- THX Mr.Murray for your help !
local function IsPlayerInSafeZone(playerId)
    local xPlayer = nil

    if Config.Framework == 'QBCore' then
        xPlayer = Framework.Functions.GetPlayer(playerId)
    elseif Config.Framework == 'ESX' then
        xPlayer = Framework.GetPlayerFromId(playerId)
    end

    if not xPlayer then return false end

    local playerPed = GetPlayerPed(GetPlayerServerId(playerId))
    local playerCoords = GetEntityCoords(playerPed)

    for _, zone in ipairs(Config.SafeZones) do
        local distance = #(vector2(playerCoords.x, playerCoords.y) - vector2(zone.coords.x, zone.coords.y))
        if distance <= zone.radius then
            return true
        end
    end

    return false
end

-- Message de démarrage
CreateThread(function()
    Wait(2000)
    print('^2[GLD-NestEvent] operational^7')
    print('^5[DISCORD SUPPORT] fabgros.^7')
    print('^2Modular compatibility with ESX or QBCore by M4lwqre.^7')
end)

-- Variables d'état
local systemEnabled = true
local activeEvent = nil
local eventTimer = nil
local eventParticipants = {}
local eventStats = {}

-- Debug avec vérification de Config
local function Debug(message, level)
    if Config and Config.NestEvent and Config.NestEvent.Debug then
        level = level or 'info'
        local colors = {
            info = '^3',
            success = '^2',
            warning = '^8',
            error = '^1'
        }
        print(string.format('%s[NEST-EVENT] %s^7', colors[level] or '^3', message))
    end
end

-- Fonctions de gestion des stats en JSON
local function LoadStats()
    local file = LoadResourceFile(GetCurrentResourceName(), "stats.json")
    local defaultStats = {
        totalEvents = 0,
        totalKills = 0,
        bestKills = 0,
        bestKiller = nil,
        totalMoneyGiven = 0,
        bestTimeBonus = 0,
        rewardHistory = {}
    }

    if file then
        local decoded = json.decode(file)
        if decoded then
            -- Fusionner avec les valeurs par défaut pour s'assurer que tous les champs existent
            for k, v in pairs(defaultStats) do
                if decoded[k] == nil then
                    decoded[k] = v
                end
            end
            eventStats = decoded
            Debug("Stats chargées depuis stats.json", "success")
        else
            Debug("Erreur de décodage des stats, initialisation par défaut", "warning")
            eventStats = defaultStats
        end
    else
        Debug("Aucun fichier de stats trouvé, initialisation par défaut", "info")
        eventStats = defaultStats
    end
end

local function SaveStats()
    local encoded = json.encode(eventStats)
    if encoded then
        SaveResourceFile(GetCurrentResourceName(), "stats.json", encoded, -1)
        Debug("Stats sauvegardées dans stats.json", "success")
    else
        Debug("Erreur lors de la sauvegarde des stats", "error")
    end
end


-- Calcul des récompenses (Compatible ESX + QBCore)
local function CalculateRewards(source, kills, timeInZone)
    local baseReward = Config.NestEvent.rewards.money.base
    local killReward = kills * Config.NestEvent.rewards.money.perKill
    local timeBonus = 0
    local totalReward = baseReward + killReward

    Debug(string.format("Calcul des récompenses pour le joueur %s:", source))
    Debug(string.format("- Récompense de base: $%d", baseReward))
    Debug(string.format("- Bonus de kills: $%d (%d kills × $%d)", 
        killReward, kills, Config.NestEvent.rewards.money.perKill))

    -- Appliquer le bonus de temps
    if timeInZone >= Config.NestEvent.rewards.money.timeBonus.requiredTime then
        timeBonus = totalReward * (Config.NestEvent.rewards.money.timeBonus.multiplier - 1)
        totalReward = totalReward * Config.NestEvent.rewards.money.timeBonus.multiplier
        Debug(string.format("- Bonus de temps appliqué: +$%d (×%.1f)", 
            timeBonus, Config.NestEvent.rewards.money.timeBonus.multiplier))
    end

    -- S'assurer que les champs existent
    if not eventStats.rewardHistory then eventStats.rewardHistory = {} end
    if not eventStats.totalMoneyGiven then eventStats.totalMoneyGiven = 0 end
    if not eventStats.bestTimeBonus then eventStats.bestTimeBonus = 0 end

    -- Enregistrer dans l'historique
    table.insert(eventStats.rewardHistory, {
        timestamp = os.time(),
        player = source,
        baseReward = baseReward,
        killReward = killReward,
        timeBonus = timeBonus,
        totalReward = totalReward,
        kills = kills,
        timeInZone = timeInZone,
        hadTimeBonus = timeBonus > 0
    })

    eventStats.totalMoneyGiven = eventStats.totalMoneyGiven + totalReward
    if timeBonus > eventStats.bestTimeBonus then
        eventStats.bestTimeBonus = timeBonus
    end

    SaveStats()
    return totalReward, timeBonus > 0
end

-- Fin de l'événement (Compatible ESX + QBCore)
local function EndNestEvent(success)
    if not activeEvent then return end
    Debug("Tentative de fin d'événement")

    -- Calcul des statistiques finales
    local totalEventKills = 0
    local bestPlayerKills = 0
    local bestPlayer = nil
    
    -- Sauvegarder les kills dans notre variable globale
    lastEventKills = activeEvent.kills or {}
    Debug("Sauvegarde des kills: " .. json.encode(lastEventKills))

    for source, kills in pairs(lastEventKills) do
        totalEventKills = totalEventKills + kills
        if kills > bestPlayerKills then
            bestPlayerKills = kills
            bestPlayer = source
        end
        Debug("Joueur " .. source .. ": " .. kills .. " kills")
    end

    -- Mise à jour des stats globales
    eventStats.totalEvents = (eventStats.totalEvents or 0) + 1
    eventStats.totalKills = (eventStats.totalKills or 0) + totalEventKills
    
    if bestPlayerKills > (eventStats.bestKills or 0) then
        eventStats.bestKills = bestPlayerKills
        eventStats.bestKiller = bestPlayer
        
        if bestPlayer then
            if Config.Framework == 'QBCore' then
                TriggerClientEvent('QBCore:Notify', bestPlayer, 
                    Config.NestEvent.GetText('messages.newRecord', bestPlayerKills),
                    'success'
                )
            elseif Config.Framework == 'ESX' then
                TriggerClientEvent('esx:showNotification', bestPlayer,
                    Config.NestEvent.GetText('messages.newRecord', bestPlayerKills)
                )
            end
            Debug("Nouveau record établi par " .. bestPlayer .. ": " .. bestPlayerKills .. " kills")
        end
    end

    SaveStats()

    -- Notifier tous les clients (Compatible ESX + QBCore)
    TriggerClientEvent('nest-event:end', -1, {
        success = success,
        stats = {
            totalKills = lastEventKills,
            participants = activeEvent.participants or {},
            eventStats = {
                totalKills = totalEventKills,
                bestKills = bestPlayerKills,
                bestPlayer = bestPlayer
            }
        }
    })
end

-- Nettoyer les timers
if eventTimer then
    clearTimeout(eventTimer)
    eventTimer = nil
end

-- Vérification que `totalEventKills` et `bestPlayerKills` sont valides
totalEventKills = totalEventKills or 0  -- Si nil, on met à 0
bestPlayerKills = bestPlayerKills or 0  -- Si nil, on met à 0
bestPlayer = bestPlayer or "aucun"  -- Si nil, on met à "aucun"

-- Affichage des statistiques de fin d'événement
Debug(string.format("Événement terminé - Total Kills: %d, Meilleur joueur: %s avec %d kills", 
    totalEventKills, 
    bestPlayer,
    bestPlayerKills
))

-- Ne pas effacer lastEventKills pour permettre la réclamation des récompenses
activeEvent = nil

-- Sélection d'un joueur aléatoire (Compatible ESX + QBCore)
local function GetRandomPlayer()
    local validPlayers = {}

    -- Initialisation du framework en fonction du config
    local Framework = nil

    if Config.Framework == 'QBCore' then
        Framework = QBCore
    elseif Config.Framework == 'ESX' then
        Framework = ESX
    end

    -- Vérification du framework et récupération des joueurs
    if Framework then
        if Config.Framework == 'QBCore' then
            local players = Framework.Functions.GetQBPlayers() -- Utilisation de QBCore
            for _, player in pairs(players) do
                if player.PlayerData.source then -- Vérifie que le joueur est connecté
                    local isValid = not player.PlayerData.metadata.isdead 
                        and not player.PlayerData.metadata.inlaststand 
                        and not IsPlayerInSafeZone(player.PlayerData.source)

                    if isValid then
                        table.insert(validPlayers, player)
                    end
                end
            end
        elseif Config.Framework == 'ESX' then
            local players = Framework.GetPlayers() -- Utilisation de ESX
            for _, playerId in ipairs(players) do
                local xPlayer = Framework.GetPlayerFromId(playerId)
                if xPlayer then
                    local isValid = not IsPlayerInSafeZone(playerId)
                    if isValid then
                        table.insert(validPlayers, xPlayer)
                    end
                end
            end
        end
    else
        Debug("Framework invalide ou non initialisé.", "error")
        return nil
    end

    return #validPlayers > 0 and validPlayers[math.random(#validPlayers)] or nil
end


-- Démarrer l'événement (Compatible ESX + QBCore)
local function StartNestEvent(targetPlayer)
    if activeEvent or not systemEnabled then 
        Debug("Impossible de démarrer: event actif ou système désactivé", "warning")
        return false
    end

    local selectedPlayer = targetPlayer or GetRandomPlayer()
    if not selectedPlayer then 
        Debug("Aucun joueur valide trouvé", "warning")
        return false
    end

    -- Récupération du ped du joueur
    local playerSource = nil
    if Config.Framework == 'QBCore' then
        playerSource = selectedPlayer.PlayerData.source
    elseif Config.Framework == 'ESX' then
        playerSource = selectedPlayer.source
    end

    local ped = GetPlayerPed(playerSource)
    if not ped then
        Debug("Impossible de trouver le ped du joueur", "error")
        return false
    end

    local x, y, z = table.unpack(GetEntityCoords(ped))
    local playerCoords = vector3(x, y, z)
    
    if not playerCoords then
        Debug("Coordonnées du joueur invalides", "error")
        return false
    end
    Debug("Coordonnées du joueur: " .. playerCoords.x .. ", " .. playerCoords.y .. ", " .. playerCoords.z)

    -- Utiliser le système de spawn prédéfini
    local spawnCoords = Spawn.GetNearestNestSpawn(playerCoords)
    
    if not spawnCoords then
        Debug("Aucun point de spawn valide trouvé dans la zone configurée", "error")
        return false
    end

    -- Vérifier que le spawn est dans les limites de distance configurées
    local distanceToPlayer = #(vector3(playerCoords.x, playerCoords.y, playerCoords.z) - spawnCoords)
    if distanceToPlayer < Config.NestEvent.area.minSpawnDistance or distanceToPlayer > Config.NestEvent.area.maxSpawnDistance then
        Debug("Point de spawn hors des limites de distance configurées", "error")
        return false
    end

    Debug("Point de spawn sélectionné: " .. json.encode(spawnCoords), "success")

    -- Réinitialiser les participants
    eventParticipants = {}

    -- Créer l'événement
    activeEvent = {
        id = "nest_" .. os.time(),
        startTime = os.time(),
        coords = spawnCoords,
        participants = {},
        kills = {},
        active = true,
        initiator = playerSource
    }

    -- Spawn le nest (Compatible ESX + QBCore)
    exports.hrs_zombies_V2:SpawnNest(
        activeEvent.id,
        Config.NestEvent.nestType,
        spawnCoords
    )

    -- Notifier les clients (Compatible ESX + QBCore)
    TriggerClientEvent('nest-event:start', -1, {
        coords = spawnCoords,
        id = activeEvent.id
    })

    -- Timer de fin avec avertissements (Compatible ESX + QBCore)
    local function SendTimeWarning(minutesLeft)
        if activeEvent then
            if Config.Framework == 'QBCore' then
                TriggerClientEvent('QBCore:Notify', -1, 
                    Config.NestEvent.GetText('messages.timeWarning', minutesLeft),
                    'inform'
                )
            elseif Config.Framework == 'ESX' then
                TriggerClientEvent('esx:showNotification', -1, 
                    Config.NestEvent.GetText('messages.timeWarning', minutesLeft)
                )
            end
        end
    end

    -- Configurer les avertissements de temps
    for _, minutes in ipairs(Config.NestEvent.timing.warningTimes) do
        local warningTime = (Config.NestEvent.timing.duration - minutes) * 60 * 1000
        if warningTime > 0 then
            SetTimeout(warningTime, function()
                SendTimeWarning(minutes)
            end)
        end
    end

    -- Timer principal
    eventTimer = SetTimeout(Config.NestEvent.timing.duration * 60 * 1000, function()
        EndNestEvent(true)
    end)

    Debug("Événement démarré: " .. activeEvent.id, "success")
    SaveStats()
    return true  -- <-- Assurez-vous que la fonction retourne true ici

end  -- <-- Ajout du `end` ici pour fermer la fonction StartNestEvent

-- Enregistrement des kills (Compatible ESX + QBCore)
RegisterNetEvent('nest-event:registerKill')
AddEventHandler('nest-event:registerKill', function()
    local source = source
    Debug("Tentative d'enregistrement de kill par: " .. source)

    if not activeEvent then 
        Debug("Pas d'événement actif", "warning")
        return 
    end
    
    if not activeEvent.kills then
        activeEvent.kills = {}
    end
    
    activeEvent.kills[source] = (activeEvent.kills[source] or 0) + 1
    Debug("Kill enregistré - Joueur: " .. source .. " - Total kills: " .. activeEvent.kills[source])

    -- Mettre à jour tous les clients
    TriggerClientEvent('nest-event:updateKills', -1, activeEvent.kills)
end)


-- Suivi des joueurs dans la zone (Compatible ESX + QBCore)
RegisterNetEvent('nest-event:updatePlayerZoneStatus')
AddEventHandler('nest-event:updatePlayerZoneStatus', function(isInZone)
    local source = source
    Debug("Mise à jour du statut de zone pour le joueur " .. source .. ": " .. tostring(isInZone))
    
    if not activeEvent then 
        Debug("Pas d'événement actif", "warning")
        return 
    end
    
    if not activeEvent.participants then
        activeEvent.participants = {}
    end
    
    if isInZone then
        eventParticipants[source] = true
        Debug("Joueur " .. source .. " ajouté aux participants éligibles")
        
        if not activeEvent.participants[source] then
            activeEvent.participants[source] = {
                timeInZone = 0,
                joinTime = os.time(),
                hasParticipated = true
            }
            Debug("Joueur " .. source .. " enregistré comme participant")
        end
    end
end)

-- Distribution des récompenses (Compatible ESX + QBCore)
RegisterNetEvent('nest-event:claimReward')
AddEventHandler('nest-event:claimReward', function(clientTimeInZone)
    local source = source
    Debug("Tentative de réclamation de récompense par: " .. source)
    
    local player = nil
    if Config.Framework == 'QBCore' then
        player = QBCore.Functions.GetPlayer(source)
    elseif Config.Framework == 'ESX' then
        player = ESX.GetPlayerFromId(source)
    end
    
    if not player then 
        Debug("Joueur non trouvé", "error")
        return 
    end
end)
   
-- Vérification de participation (Compatible ESX + QBCore)
RegisterNetEvent('nest-event:claimReward')
AddEventHandler('nest-event:claimReward', function(clientTimeInZone)
    local source = source
    Debug("Tentative de réclamation de récompense par: " .. source)
    
    local player = nil
    if Config.Framework == 'QBCore' then
        player = QBCore.Functions.GetPlayer(source)
    elseif Config.Framework == 'ESX' then
        player = ESX.GetPlayerFromId(source)
    end
    
    if not player then 
        Debug("Joueur non trouvé", "error")
        return 
    end

    -- Vérification de la participation
    if not eventParticipants[source] then
        Debug("Joueur " .. source .. " n'a pas participé à l'événement", "warning")
        TriggerClientEvent('nest-event:rewardError', source, 'notParticipated')
        return
    end

    -- Utiliser les kills sauvegardés
    local kills = lastEventKills[source] or 0
    Debug("Kills pour le joueur " .. source .. ": " .. kills)

    -- Calcul des récompenses avec bonus
    local totalReward, hadTimeBonus = CalculateRewards(source, kills, clientTimeInZone)
    Debug("Récompense calculée: $" .. totalReward .. " (avec " .. kills .. " kills)")
    
   -- Donner l'argent en tant qu'item
if Config.Framework == 'QBCore' then
    -- Ajout de l'argent comme item (ex. 'money')
    if player.Functions.AddItem('money', totalReward) then
        Debug("Argent donné: $" .. totalReward)
    else
        Debug("Erreur lors de l'ajout de l'argent dans l'inventaire du joueur", "error")
    end
elseif Config.Framework == 'ESX' then
    -- Ajout de l'argent comme item (ex. 'money')
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer then
        if xPlayer.canCarryItem('money', totalReward) then
            xPlayer.addInventoryItem('money', totalReward)
            Debug("Argent donné: $" .. totalReward)
        else
            TriggerClientEvent('esx:showNotification', source, 
                Config.NestEvent.GetText('messages.reward.inventoryFull')
            )
        end
    end
end

    
    -- Items de récompense
    local givenItems = {}

    -- Items standards
    for _, item in ipairs(Config.NestEvent.rewards.items.standard) do
        if math.random(100) <= item.chance then
            local amount = math.random(item.amount.min, item.amount.max)
            
            -- Vérifie le framework utilisé (ESX ou QBCore)
            if Config.Framework == 'QBCore' then
                -- Utilisation de QBCore
                if player.Functions.AddItem(item.name, amount) then
                    table.insert(givenItems, {name = item.name, amount = amount})
                    Debug("Item donné: " .. item.name .. " x" .. amount)
                else
                    TriggerClientEvent('QBCore:Notify', source, 
                        Config.NestEvent.GetText('messages.reward.inventoryFull'),
                        'error'
                    )
                    break
                end
            elseif Config.Framework == 'ESX' then
                -- Utilisation de ESX
                local xPlayer = ESX.GetPlayerFromId(source)  -- Récupérer le joueur ESX
                if xPlayer then
                    if xPlayer.canCarryItem(item.name, amount) then
                        xPlayer.addInventoryItem(item.name, amount)
                        table.insert(givenItems, {name = item.name, amount = amount})
                        Debug("Item donné: " .. item.name .. " x" .. amount)
                    else
                        TriggerClientEvent('esx:showNotification', source, 
                            Config.NestEvent.GetText('messages.reward.inventoryFull')
                        )
                        break
                    end
                end
            end
        end
    end
    
-- Items rares (si assez de kills)
if kills >= Config.NestEvent.rewards.conditions.minKills then
    for _, item in ipairs(Config.NestEvent.rewards.items.rare) do
        if math.random(100) <= item.chance then
            -- Vérifie quel framework est utilisé
            if Config.Framework == 'QBCore' then
                -- Utilisation de QBCore
                if player.Functions.AddItem(item.name, item.amount) then
                    table.insert(givenItems, {name = item.name, amount = item.amount})
                    Debug("Item rare donné: " .. item.name .. " x" .. item.amount)
                end
            elseif Config.Framework == 'ESX' then
                -- Utilisation de ESX
                local xPlayer = ESX.GetPlayerFromId(source)  -- Récupérer le joueur ESX
                if xPlayer then
                    if xPlayer.canCarryItem(item.name, item.amount) then
                        xPlayer.addInventoryItem(item.name, item.amount)
                        table.insert(givenItems, {name = item.name, amount = item.amount})
                        Debug("Item rare donné: " .. item.name .. " x" .. item.amount)
                    else
                        TriggerClientEvent('esx:showNotification', source, 
                            Config.NestEvent.GetText('messages.reward.inventoryFull')
                        )
                    end
                end
            end
        end
    end
end

    
    -- Notifier le client (Compatible ESX + QBCore)
    TriggerClientEvent('nest-event:rewardClaimed', source, {
        money = totalReward,
        items = givenItems,
        timeBonus = hadTimeBonus,
        stats = {
            kills = kills,
            wasTopKiller = kills == eventStats.bestKills
        }
    })

    -- Retirer le joueur des participants éligibles
    eventParticipants[source] = nil
    Debug("Distribution des récompenses terminée pour le joueur " .. source)
    
    -- Sauvegarder les stats
    eventStats.totalMoneyGiven = (eventStats.totalMoneyGiven or 0) + totalReward
    SaveStats()
end)

-- Thread principal avec vérification automatique (Compatible ESX + QBCore)
CreateThread(function()
    -- Charger les stats au démarrage
    Wait(1000)
    LoadStats()
    
    while true do
        Wait(Config.NestEvent.timing.checkInterval * 60 * 1000)
        
        if systemEnabled and not activeEvent then
            local hour = tonumber(os.date("%H"))
            local chance = (hour >= 20 or hour <= 6) 
                and Config.NestEvent.timing.nightChance 
                or Config.NestEvent.timing.dayChance

            local players = nil
            local playerCount = 0
            
            if Config.Framework == 'QBCore' then
                players = QBCore.Functions.GetQBPlayers()
            elseif Config.Framework == 'ESX' then
                players = ESX.GetPlayers()
            end

            for _ in pairs(players) do playerCount = playerCount + 1 end
            
            local adjustedChance = chance + (playerCount * 2)
            Debug(string.format("Chance d'événement: %d%% (Base: %d%%, Bonus joueurs: %d%%)", 
                adjustedChance, chance, playerCount * 2))

            if math.random(100) <= adjustedChance then
                StartNestEvent()
            end
        end
    end
end)


-- Commandes Admin (Compatible ESX + QBCore)
if Config.Framework == 'QBCore' then
    QBCore.Commands.Add('forcenest', 'Force un événement nest (Admin)', {{name = 'playerid', help = 'ID du joueur (optionnel)'}}, true, function(source, args)
        if QBCore.Functions.HasPermission(source, 'admin') then
            local targetSource = tonumber(args[1])
            if targetSource then
                local player = QBCore.Functions.GetPlayer(targetSource)
                if player then
                    if activeEvent then EndNestEvent(false) end
                    StartNestEvent(player)
                end
            else
                if activeEvent then EndNestEvent(false) end
                StartNestEvent()
            end
        end
    end)

    QBCore.Commands.Add('clearnest', 'Nettoie l\'événement en cours (Admin)', {}, true, function(source)
        if QBCore.Functions.HasPermission(source, 'admin') then
            if activeEvent then
                EndNestEvent(false)
                TriggerClientEvent('QBCore:Notify', source, 
                    Config.NestEvent.GetText('messages.admin.eventCleaned'),
                    'success'
                )
            end
        end
    end)

    QBCore.Commands.Add('togglenest', 'Active/Désactive le système de nest events (Admin)', {}, true, function(source)
        if QBCore.Functions.HasPermission(source, 'admin') then
            systemEnabled = not systemEnabled
            
            if not systemEnabled and activeEvent then
                EndNestEvent(false)
            end

            TriggerClientEvent('QBCore:Notify', source, 
                Config.NestEvent.GetText(systemEnabled and 'messages.admin.systemEnabled' or 'messages.admin.systemDisabled'),
                'success'
            )
            
            Debug(string.format("Système %s par %s", 
                systemEnabled and "activé" or "désactivé",
                GetPlayerName(source)
            ))
        end
    end)
elseif Config.Framework == 'ESX' then
    ESX.RegisterCommand('forcenest', 'admin', function(source, args, user)
        local targetSource = tonumber(args[1])
        if targetSource then
            local player = ESX.GetPlayerFromId(targetSource)
            if player then
                if activeEvent then EndNestEvent(false) end
                StartNestEvent(player)
            end
        else
            if activeEvent then EndNestEvent(false) end
            StartNestEvent()
        end
    end, false)

    ESX.RegisterCommand('clearnest', 'admin', function(source, args, user)
        if activeEvent then
            EndNestEvent(false)
            TriggerClientEvent('esx:showNotification', source, 
                Config.NestEvent.GetText('messages.admin.eventCleaned')
            )
        end
    end, false)

    ESX.RegisterCommand('togglenest', 'admin', function(source, args, user)
        systemEnabled = not systemEnabled
        
        if not systemEnabled and activeEvent then
            EndNestEvent(false)
        end

        TriggerClientEvent('esx:showNotification', source, 
            Config.NestEvent.GetText(systemEnabled and 'messages.admin.systemEnabled' or 'messages.admin.systemDisabled')
        )
        
        Debug(string.format("Système %s par %s", 
            systemEnabled and "activé" or "désactivé",
            GetPlayerName(source)
        ))
    end, false)
end

-- Nettoyage à l'arrêt de la ressource (Compatible ESX + QBCore)
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    if activeEvent then
        EndNestEvent(false)
    end
    
    SaveStats()
end)

-- Vérification des routes (Compatible ESX + QBCore)
RegisterNetEvent('nest-event:roadCheckResult')
AddEventHandler('nest-event:roadCheckResult', function(coords, isValid)
    Debug(string.format("Résultat vérification route: %s pour coords %s", 
        tostring(isValid), 
        json.encode(coords)))
end)
