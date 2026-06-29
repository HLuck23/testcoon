-- ============================================================
-- PVP WEAPONS CONFIGURATION
-- Global Gun Rotation - Expandable for future gamemodes
-- ============================================================

-- Global rotation pool (all players get the same random pick from this)
GunRotationList = {
    {hash = "weapon_iceglock", name = "Ice Glock"},
    {hash = "weapon_badgedeagle", name = "Badged Eagle"},
    {hash = "weapon_blackiceglock", name = "Black Ice Glock"},
    {hash = "weapon_glock18dt", name = "Glock 18DT"},
    {hash = "weapon_nbk", name = "NBK"},
    {hash = "weapon_revolver357", name = "Revolver 357"},
    {hash = "weapon_hotshotwelder", name = "Hotshot Welder"},
    {hash = "weapon_ibak", name = "IBAK"},
    {hash = "weapon_m4a1sgyspunkred", name = "M4A1 Gyspunk Red"},
    {hash = "weapon_m4hyperbeast", name = "M4 Hyperbeast"},
    {hash = "weapon_retrom4a4", name = "Retro M4A4"},
    {hash = "weapon_junker", name = "Junker"},
    {hash = "weapon_crimsonsnowvector", name = "Crimson Snow Vector"},
    {hash = "weapon_blackicemp7", name = "Black Ice MP7"},
    {hash = "weapon_p90", name = "P90"},
    {hash = "weapon_spaceflightmp5", name = "Spaceflight MP5"},
    {hash = "weapon_acrcqb", name = "ACR CQB"},
    {hash = "weapon_asm1", name = "ASM1"},
    {hash = "weapon_blastxspectre", name = "BlastX Spectre"},
    {hash = "weapon_candymp5", name = "Candy MP5"},
    {hash = "weapon_coldhunterthompson", name = "Cold Hunter Thompson"},
    {hash = "weapon_cx9", name = "CX-9"},
    {hash = "weapon_dssmg", name = "DS SMG"},
    {hash = "weapon_icevector", name = "Ice Vector"},
    {hash = "weapon_minicarbine", name = "Mini Carbine"},
    {hash = "weapon_mp40type2", name = "MP40 Type 2"},
    {hash = "weapon_r99", name = "R-99"},
    {hash = "weapon_tbsvector", name = "TBS Vector"},
    {hash = "weapon_vesperhybrid", name = "Vesper Hybrid"},
    {hash = "weapon_vss", name = "VSS"},
    {hash = "weapon_nailgun", name = "Nailgun"},
    {hash = "weapon_glock17s", name = "Glock 17S"},
    {hash = "weapon_glock30", name = "Glock 30"},
    {hash = "weapon_glock34", name = "Glock 34"},
    {hash = "WEAPON_ICEDBONGSHOT", name = "Iced Bong Shot"},
    {hash = "WEAPON_ICEDFAL", name = "Iced FAL"},
    {hash = "WEAPON_ICEDGLOCK", name = "Iced Glock"},
    {hash = "WEAPON_ICEDMZA", name = "Iced MZA"},
    {hash = "WEAPON_ICEDP90", name = "Iced P90"},
    {hash = "WEAPON_ICEDQP12", name = "Iced QP12"},
    {hash = "WEAPON_ICEDR4C", name = "Iced R4-C"},
    {hash = "w_sb_minismg", name = "Mini SMG"},
    {hash = "WEAPON_KURONAMIVANDAL", name = "Kuronami Vandal"},
}

-- Legacy weapon names (keep for kill-feed / other modes compatibility)
WeaponNames = {
    [GetHashKey("WEAPON_UNARMED")] = "Fists",
    [GetHashKey("WEAPON_KNIFE")] = "Knife",
    [GetHashKey("WEAPON_PISTOL")] = "Pistol",
    [GetHashKey("WEAPON_COMBATPISTOL")] = "Combat Pistol",
    [GetHashKey("WEAPON_HEAVYPISTOL")] = "Heavy Pistol",
    [GetHashKey("WEAPON_APPISTOL")] = "AP Pistol",
    [GetHashKey("WEAPON_GRENADE")] = "Grenade",
    [GetHashKey("WEAPON_STICKYBOMB")] = "Sticky Bomb",
    [GetHashKey("WEAPON_MOLOTOV")] = "Molotov",
    [GetHashKey("WEAPON_RPG")] = "RPG",
    [GetHashKey("WEAPON_MINIGUN")] = "Minigun",
    [GetHashKey("WEAPON_ASSAULTRIFLE")] = "Assault Rifle",
    [GetHashKey("WEAPON_SPECIALCARBINE")] = "Special Carbine",
    [GetHashKey("WEAPON_BULLPUPRIFLE")] = "Bullpup Rifle",
    [GetHashKey("WEAPON_PUMPSHOTGUN")] = "Pump Shotgun",
    [GetHashKey("WEAPON_ASSAULTSHOTGUN")] = "Assault Shotgun",
    [GetHashKey("WEAPON_SNIPERRIFLE")] = "Sniper Rifle",
    [GetHashKey("WEAPON_HEAVYSNIPER")] = "Heavy Sniper",
    [GetHashKey("WEAPON_MARKSMANRIFLE")] = "Marksman Rifle",
    [GetHashKey("WEAPON_COMBATMG")] = "Combat MG",
    [GetHashKey("WEAPON_MG")] = "MG",
    [GetHashKey("WEAPON_SMG")] = "SMG",
    [GetHashKey("WEAPON_MICROSMG")] = "Micro SMG",
    [GetHashKey("w_sb_minismg")] = "Mini SMG",
}

-- Auto-register rotation weapons into the name lookup
for _, gun in ipairs(GunRotationList) do
    local hash = GetHashKey(gun.hash)
    WeaponNames[hash] = gun.name
end

function GetWeaponDisplayName(hash)
    return WeaponNames[hash] or "Weapon"
end