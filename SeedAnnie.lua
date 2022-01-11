module("SeedAnnie", package.seeall, log.setup)
clean.module("SeedAnnie", package.seeall, log.setup)

-- Globals
local CoreEx = _G.CoreEx
local Libs = _G.Libs

local Menu = Libs.NewMenu
local Prediction = Libs.Prediction
local Orbwalker = Libs.Orbwalker
local CollisionLib = Libs.CollisionLib
local DamageLib = Libs.DamageLib
local SpellLib = Libs.Spell
local TargetSelector = Libs.TargetSelector

local ObjectManager = CoreEx.ObjectManager
local EventManager = CoreEx.EventManager
local Input = CoreEx.Input
local Enums = CoreEx.Enums
local Game = CoreEx.Game
local Geometry = CoreEx.Geometry
local Renderer = CoreEx.Renderer

local SpellSlots = Enums.SpellSlots
local SpellStates = Enums.SpellStates
local BuffTypes = Enums.BuffTypes
local Events = Enums.Events
local HitChance = Enums.HitChance
local HitChanceStrings = {"Collision", "OutOfRange", "VeryLow", "Low", "Medium", "High", "VeryHigh", "Dashing",
                          "Immobile"};

local Player = ObjectManager.Player.AsHero
if Player.CharName ~= "Annie" then
    return false
end

-- Spells
local Q = SpellLib.Active({
    Slot = SpellSlots.Q,
    Range = 625
})

local W = SpellLib.Skillshot({
    Slot = SpellSlots.W,
    Speed = 999,
    Range = 625,
    Delay = 0.25,
    Type = "Cone"
})
local E = SpellLib.Active({
    Slot = SpellSlots.E,
    Range = 800
})
local R = SpellLib.Active({
    Slot = SpellSlots.R,
    Range = 600,
    Delay = 0.25,
    Radius = 290
})

local Utils = {}
local Annie = {}
Annie.Menu = nil
Annie.TargetSelector = nil
Annie.Logic = {}

function Utils.StringContains(str, sub)
    return string.find(str, sub, 1, true) ~= nil
end

function Utils.GameAvailable()
    return not (Game.IsChatOpen() or Game.IsMinimized() or Player.IsDead or Player.IsRecalling)
end

function Utils.WithinMinRange(Target, Min)
    local Distance = Player:EdgeDistance(Target.Position)
    if Distance >= Min then
        return true
    end
    return false
end

function Utils.WithinMaxRange(Target, Max)
    local Distance = Player:EdgeDistance(Target.Position)
    if Distance <= Max then
        return true
    end
    return false
end

function Utils.HasBuff(target, buff)
    for i, v in pairs(target.Buffs) do
        if v.Name == buff then
            return true
        end
    end
    return false
end

function Utils.InRange(Range, Type)
    -- return target count in range
    return #(Annie.TargetSelector:GetValidTargets(Range, ObjectManager.Get("enemy", Type), false))
end

function Annie.Logic.BuffCount()
    local buff = Player:GetBuff("anniepassivestack")
    local buff1 = Player:GetBuff("anniepassiveprimed")
    if buff then
        return (buff.Count)
    end
    if not buff and buff1 then
        return 4
    end
    if not buff and not buff1 then
        return 0
    end
    return false
end
function Annie.Logic.TibbersActive()
    for _, v in pairs(ObjectManager.Get("ally", "minions")) do
        local minion = v.AsMinion
        if minion.Name == "Tibbers" and minion.IsAlive then
            return true
        end
    end
end
function Annie.Logic.StackPassive(MustUse)
    if not MustUse then
        return
    end
    if Player.Mana / Player.MaxMana * 100 >= Menu.Get("Misc.MinMana") and E:IsReady() and Annie.Logic.BuffCount() < 4 then
        return Input.Cast(SpellSlots.E, Player.Position)
    end
end

function Annie.Logic.StackFountain(MustUse)
    if not MustUse then
        return
    end
    if not Player.IsInFountain then
        return
    end
    if Annie.Logic.BuffCount() < 4 then
        if E:IsReady() then
            return Input.Cast(SpellSlots.E, Player.Position)
        end
        if W:IsReady() then
            return Input.Cast(SpellSlots.W, Player.Position)
        end
    end
end

function Annie.Logic.CalcQDmg(Target)
    local Level = Q:GetLevel()
    local Base = {80, 115, 150, 185, 220}
    local BaseDamage = (Base[Level]) + (0.75 * Player.BonusAP)
    return DamageLib.CalculateMagicalDamage(Player, Target, BaseDamage)
end

function Annie.Logic.CalcWDmg(Target)
    local Level = W:GetLevel()
    local Base = {70, 115, 160, 205, 250}

    local BaseDamage = (Base[Level]) + (0.85 * Player.BonusAP)
    return DamageLib.CalculateMagicalDamage(Player, Target, BaseDamage)
end

function Annie.Logic.CalcRDmg(Target)
    local Level = R:GetLevel()
    local Base = {150, 275, 400}
    local BaseDamage = (Base[Level]) + (0.75 * Player.BonusAP)
    return DamageLib.CalculateMagicalDamage(Player, Target, BaseDamage)
end

function Annie.Logic.Q(MustUse)
    if not MustUse then
        return false
    end
    local QTarget = Q:GetTarget()
    if (QTarget and QTarget.IsAlive and Q:IsReady() and QTarget.Position:Distance(Player.Position) <= Q.Range) then
        if Input.Cast(SpellSlots.Q, QTarget) then
            return true
        end
    end
    return false
end

function Annie.Logic.W(MustUse)
    if not MustUse then
        return false
    end
    local QTarget = Q:GetTarget()
    if (QTarget and W:IsReady() and QTarget.Position:Distance(Player.Position) <= W.Range) then
        if Input.Cast(SpellSlots.W, QTarget.Position) then
            return true
        end
    end
    return false
end

function Annie.Logic.E(MustUse)
    if not MustUse then
        return false
    end
    local QTarget = Q:GetTarget()
    if Menu.Get("Combo.E.Use") then
        if (QTarget and Annie.Logic.BuffCount() == 3 and E:IsReady() and QTarget.Position:Distance(Player.Position) <=
            Q.Range) then
            if Input.Cast(SpellSlots.E, Player.Position) then
                return true
            end
        end
    end
    return false
end

function Annie.Logic.R(MustUse)
    if not MustUse then
        return false
    end
    local rPositions = {}
    if R:IsReady() and not Annie.Logic.TibbersActive() then
        for _, v in pairs(ObjectManager.Get("enemy", "heroes")) do
            local target = v.AsHero
            if target.IsAlive and target.Position:Distance(Player.Position) <= R.Range then
                local rPos = target:FastPrediction(R.Delay)
                table.insert(rPositions, rPos)
            end
        end
        if #rPositions > 0 then
            local bestWPos, wHitCount = Geometry.BestCoveringCircle(rPositions, R.Radius)
            if wHitCount >= Menu.Get("Combo.R.MinHit") then
                if Input.Cast(SpellSlots.R, bestWPos) then
                    return true
                end
            end
        end
    end
    return false
end

function Annie.OnProcessSpell(Caster, SpellCast)
    if Player.IsRecalling then
        return
    end
    --
end
function Annie.OnDrawDamage(target, dmgList)
    local dmg = 0
    if Q:IsReady() then
        dmg = dmg + Annie.Logic.CalcQDmg(target)
    end
    if W:IsReady() then
        dmg = dmg + Annie.Logic.CalcWDmg(target)
    end
    if R:IsReady() then
        dmg = dmg + Annie.Logic.CalcRDmg(target)
    end
    table.insert(dmgList, dmg)
end

function Annie.OnHeroImmobilized(Source, EndTime, IsStasis)
    if Player.IsRecalling then
        return
    end

end

function Annie.Logic.Combo()
    if (Annie.Logic.E(Menu.Get("Combo.E.Use"))) then
        return true
    end
    if (Annie.Logic.Q(Menu.Get("Combo.Q.Use"))) then
        return true
    end
    if (Annie.Logic.W(Menu.Get("Combo.W.Use"))) then
        return true
    end
    if (Annie.Logic.R(Menu.Get("Combo.R.Use"))) then
        return true
    end
    return false
end

function Annie.Logic.Harass()
    if (Menu.Get("Harass.WasteStack") and Annie.Logic.BuffCount() <= 4) or
        (not Menu.Get("Harass.WasteStack") and Annie.Logic.BuffCount() < 4) then
        if (Annie.Logic.Q(Menu.Get("Harass.Q.Use"))) then
            return true
        end
        if (Annie.Logic.W(Menu.Get("Harass.W.Use"))) then
            return true
        end
    end
end

function Utils.ValidMinion(minion)
    return minion and minion.IsTargetable and not minion.IsDead and minion.MaxHealth > 6
end

function Annie.Logic.Lasthit()
    local SortbyHealth = 1000
    if Menu.Get("LastHit.Q.Use") and Q:IsReady() then
        if Player.Mana / Player.MaxMana * 100 >= Menu.Get("LastHit.MinMana") then
            if (Menu.Get("LastHit.Q.WasteStack") and Annie.Logic.BuffCount() <= 4) or
                (not Menu.Get("LastHit.Q.WasteStack") and Annie.Logic.BuffCount() < 4) then
                for _, v in pairs(ObjectManager.Get("neutral", "minions")) do
                    if v.IsAlive and v.Health <= SortbyHealth and Annie.Logic.CalcQDmg(v) > v.Health and
                        v.Position:Distance(Player.Position) <= Q.Range and not Orbwalker.IsWindingUp() then
                        return Input.Cast(SpellSlots.Q, v)
                    end
                end
                for _, v in pairs(ObjectManager.Get("enemy", "minions")) do
                    if v.IsAlive and v.Health <= SortbyHealth and Annie.Logic.CalcQDmg(v) > v.Health and
                        v.Position:Distance(Player.Position) <= Q.Range and not Orbwalker.IsWindingUp() then
                        return Input.Cast(SpellSlots.Q, v)
                    end
                end
            end
        end
    end
    return false
end
function Annie.Logic.Flee()
    if E:IsReady() then
        if Input.Cast(SpellSlots.E, Player.Position) then
            return true
        end
    end
    return false
end

function Annie.Logic.Waveclear()
    local SortbyHealth = 1000
    if Menu.Get("LaneClear.W.Use") and W:IsReady() then
        if Player.Mana / Player.MaxMana * 100 >= Menu.Get("LaneClear.MinMana") then
            if (Menu.Get("LaneClear.Q.WasteStack") and Annie.Logic.BuffCount() <= 4) or
                (not Menu.Get("LaneClear.Q.WasteStack") and Annie.Logic.BuffCount() < 4) then
                local minionsPositions = {}
                for _, v in pairs(ObjectManager.Get("enemy", "minions")) do
                    local minion = v.AsMinion
                    if minion.Position:Distance(Player.Position) <= W.Range and minion.IsAlive then
                        table.insert(minionsPositions, minion.Position)
                    end
                end
                if #minionsPositions > 0 then
                    local bestPos, numberOfHits = Geometry.BestCoveringCone(minionsPositions, Player.Position, 40)
                    if bestPos and numberOfHits >= Menu.Get("LaneClear.W.Min") and not Orbwalker.IsWindingUp() then
                        return Input.Cast(SpellSlots.W, bestPos)
                    end
                end
            end
        end
    end
    if Menu.Get("LaneClear.Q.Use") and Q:IsReady() then
        if Player.Mana / Player.MaxMana * 100 >= Menu.Get("LaneClear.MinMana") then
            if (Menu.Get("LaneClear.Q.WasteStack") and Annie.Logic.BuffCount() <= 4) or
                (not Menu.Get("LaneClear.Q.WasteStack") and Annie.Logic.BuffCount() < 4) then
                for _, v in pairs(ObjectManager.Get("neutral", "minions")) do
                    if v.IsAlive and v.Health <= SortbyHealth and Annie.Logic.CalcQDmg(v) > v.Health and
                        v.Position:Distance(Player.Position) <= Q.Range and not Orbwalker.IsWindingUp() then
                        return Input.Cast(SpellSlots.Q, v)
                    end
                end
                for _, v in pairs(ObjectManager.Get("enemy", "minions")) do
                    if v.IsAlive and v.Health <= SortbyHealth and Annie.Logic.CalcQDmg(v) > v.Health and
                        v.Position:Distance(Player.Position) <= Q.Range and not Orbwalker.IsWindingUp() then
                        return Input.Cast(SpellSlots.Q, v)
                    end
                end
            end
        end
    end
    return false
end

function Annie.Logic.Killsteal()
    if Menu.Get("Killsteal.Q.Use") or Menu.Get("Killsteal.W.Use") or Menu.Get("Killsteal.R.Use") then
        for _, v in pairs(ObjectManager.Get("ally", "heroes")) do
            local ally = v.AsHero
            if not ally.IsMe and not ally.IsDead then
                for _, b in pairs(ObjectManager.Get("enemy", "heroes")) do
                    local enemy = b.AsHero
                    if not enemy.IsDead and enemy.IsTargetable then
                        if Menu.Get("Killsteal.Q.Use") and Q:IsReady() and Q:IsInRange(enemy) then
                            if enemy.Health <= Annie.Logic.CalcQDmg(enemy) then
                                return Input.Cast(SpellSlots.Q, enemy)
                            end
                        end
                        if Menu.Get("Killsteal.W.Use") and W:IsReady() and W:IsInRange(enemy) then
                            if enemy.Health <= Annie.Logic.CalcWDmg(enemy) then
                                return Input.Cast(SpellSlots.W, enemy)
                            end
                        end
                        if Menu.Get("Killsteal.R.Use") and not Annie.Logic.TibbersActive() and R:IsReady() and
                            R:IsInRange(enemy) then
                            if enemy.Health <= Annie.Logic.CalcRDmg(enemy) then
                                return Input.Cast(SpellSlots.R, enemy)
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end
function Annie.OnCreateObject(Object)
    --
end

function Annie.OnDeleteObject(Object)
    --
end
function Annie.LoadMenu()
    Menu.RegisterMenu("SeedAnnie", "Seed's Annie", function()
        Menu.NewTree("Annie.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Casting", "Casting", 2, true, function()
                Menu.ColoredText("Combo", 0xB65A94FF, true)
                Menu.ColoredText("> E Shield stack on 3", 0x0066CCFF, false)
                Menu.Checkbox("Combo.E.Use", "Use", true)
                Menu.ColoredText("> Q", 0x0066CCFF, false)
                Menu.Checkbox("Combo.Q.Use", "Use", true)
                Menu.ColoredText("> W", 0x0066CCFF, false)
                Menu.Checkbox("Combo.W.Use", "Use", true)
                Menu.ColoredText("> R", 0x0066CCFF, false)
                Menu.Checkbox("Combo.R.Use", "Use", true)
                Menu.Slider("Combo.R.MinHit", "Min Hit", 2, 1, 5, 1)
                Menu.NextColumn()
                Menu.ColoredText("Harass", 0xB65A94FF, true)
                Menu.ColoredText("> Waste Pyromancer", 0x0066CCFF, false)
                Menu.Checkbox("Harass.WasteStack", "Use", true)
                Menu.ColoredText("> Q", 0x0066CCFF, false)
                Menu.Checkbox("Harass.Q.Use", "Use", true)
                Menu.ColoredText("> W", 0x0066CCFF, false)
                Menu.Checkbox("Harass.W.Use", "Use", true)
            end)
        end)
        Menu.NewTree("Annie.farmMenu", "Farm Settings", function()
            Menu.ColumnLayout("Farm", "Farm", 2, true, function()
                Menu.ColoredText("LaneClear", 0xB65A94FF, true)
                Menu.Slider("LaneClear.MinMana", "Min Mana", 1, 0, 100, 5)
                Menu.ColoredText("> Waste Pyromancer", 0x0066CCFF, false)
                Menu.Checkbox("LaneClear.Q.WasteStack", "Use", false)
                Menu.ColoredText("> Q", 0x0066CCFF, false)
                Menu.Checkbox("LaneClear.Q.Use", "Use", true)
                Menu.ColoredText("> W", 0x0066CCFF, false)
                Menu.Checkbox("LaneClear.W.Use", "Use", true)
                Menu.Slider("LaneClear.W.Min", "Min Units", 3, 1, 5, 1)
                Menu.NextColumn()
                Menu.ColoredText("Last Hit", 0xB65A94FF, true)
                Menu.Slider("LastHit.MinMana", "Min Mana", 1, 0, 100, 5)
                Menu.ColoredText("> Waste Pyromancer", 0x0066CCFF, false)
                Menu.Checkbox("LastHit.Q.WasteStack", "Use", true)
                Menu.ColoredText("> Q", 0x0066CCFF, false)
                Menu.Checkbox("LastHit.Q.Use", "Use", true)

            end)
        end)
        Menu.NewTree("Annie.ksMenu", "Killsteal Settings", function()
            Menu.ColumnLayout("Killsteal", "Killsteal", 2, true, function()
                Menu.ColoredText("Killsteal", 0xB65A94FF, true)
                Menu.ColoredText("> Q", 0x0066CCFF, false)
                Menu.Checkbox("Killsteal.Q.Use", "Use", true)
                Menu.ColoredText("> W", 0x0066CCFF, false)
                Menu.Checkbox("Killsteal.W.Use", "Use", true)
                Menu.ColoredText("> R", 0x0066CCFF, false)
                Menu.Checkbox("Killsteal.R.Use", "Use", false)
            end)
        end)
        Menu.NewTree("Annie.fleeMenu", "Flee Settings", function()
            Menu.ColumnLayout("Flee", "Flee", 2, true, function()
                Menu.ColoredText("Flee", 0xB65A94FF, true)
                Menu.ColoredText("> E", 0x0066CCFF, false)
                Menu.Checkbox("Flee.E.Use", "Use", true)
            end)
        end)
        Menu.NewTree("Annie.miscSettings", "Dash/Immobilize Settings", function()
            Menu.ColumnLayout("Events", "Events", 2, true, function()
                Menu.ColoredText("On Dash", 0xB65A94FF, true)
                Menu.ColoredText("> PlaceHolder  ", 0x0066CCFF, false)
                Menu.NextColumn()
                Menu.ColoredText("On Immobilize", 0xB65A94FF, true)
                Menu.ColoredText("> PlaceHolder  ", 0x0066CCFF, false)
            end)
        end)
        Menu.Separator()
        Menu.ColumnLayout("JungleSteal", "Jungle Steal", 1, true, function()
            Menu.ColoredText("Jungle Steal", 0xB65A94FF, true)
            Menu.Keybind("JungleSteal.HotKey", "HotKey", string.byte('T'))
        end)
        Menu.Separator()
        Menu.ColumnLayout("Drawings", "Drawings", 2, true, function()
            Menu.ColoredText("Misc", 0xB65A94FF, true)
            Menu.ColoredText("Stack Passive", 0xB65A94FF, true)
            Menu.Slider("Misc.MinMana", "Min Mana", 40, 0, 100, 5)

            Menu.ColoredText("> E ", 0x0066CCFF, false)
            Menu.Checkbox("Misc.E.Stack", "Use", true)
            Menu.ColoredText("> E,W ", 0x0066CCFF, false)
            Menu.Checkbox("Misc.StackFountain", "Stack in Fountain", true)

            Menu.NextColumn()
            Menu.ColoredText("Drawings", 0xB65A94FF, true)
            Menu.Checkbox("Drawings.Q", "Q", true)
            Menu.ColorPicker("Drawings.Q.Color", "", 0xEF476FFF)
            Menu.Checkbox("Drawings.W", "W", true)
            Menu.ColorPicker("Drawings.W.Color", "", 0xEF476FFF)
            Menu.Checkbox("Drawings.E", "E", true)
            Menu.ColorPicker("Drawings.E.Color", "", 0xEF476FFF)
            Menu.Checkbox("Drawings.R", "R", true)
            Menu.ColorPicker("Drawings.R.Color", "", 0xEF476FFF)
        end)
    end)
end

function Annie.OnDraw()
    if not Player.IsOnScreen or Player.IsDead then
        return false
    end
    if Menu.Get("Drawings.Q") then
        Renderer.DrawCircle3D(Player.Position, Q.Range, 30, 1, Menu.Get("Drawings.Q.Color"), 100)
    end
    if Menu.Get("Drawings.W") then
        Renderer.DrawCircle3D(Player.Position, W.Range, 30, 1, Menu.Get("Drawings.W.Color"), 100)
    end
    if Menu.Get("Drawings.E") then
        Renderer.DrawCircle3D(Player.Position, E.Range, 30, 1, Menu.Get("Drawings.E.Color"), 100)
    end
    if Menu.Get("Drawings.R") then
        Renderer.DrawCircle3D(Player.Position, R.Range, 30, 1, Menu.Get("Drawings.R.Color"), 100)
    end
    return true
end

function Annie.OnTick()
    -- Check if game is available to do anything
    if not Utils.GameAvailable() then
        return false
    end
    -- Get current orbwalker mode
    local OrbwalkerMode = Orbwalker.GetMode()

    -- Get the right logic func
    local OrbwalkerLogic = Annie.Logic[OrbwalkerMode]

    -- Call it
    if OrbwalkerLogic then
        return OrbwalkerLogic()
    end
    -- Auto stuff
    Annie.Logic.Killsteal()
    if Annie.Logic.StackPassive(Menu.Get("Misc.E.Stack")) then
        return true
    end
    if Annie.Logic.StackFountain(Menu.Get("Misc.StackFountain")) then
        return true
    end
    return true
end

function OnLoad()
    -- Load our menu
    Annie.LoadMenu()
    -- Load our target selector
    Annie.TargetSelector = TargetSelector()
    -- Register callback for func available in champion object
    for EventName, EventId in pairs(Events) do
        if Annie[EventName] then
            EventManager.RegisterCallback(EventId, Annie[EventName])
        end
    end

    return true
end
