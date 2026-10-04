--- lang/en.lua  -  English string table.
---
--- Keys are lowercase snake_case.  Values are plain text  -  no ESO color
--- markup (|cRRGGBB...|r).  Colors are applied at call sites via core/Fmt.lua
--- so translators only deal with text, not markup.
---
--- Placeholders:
---   %s          a substituted value (player name, pre-formatted timer, etc.)
---   %%          a literal percent sign (not a placeholder)
---
--- Timer and percentage values are pre-formatted in Lua via Fmt.timer() and
--- Fmt.pct() before being passed here, so no %.Nf or %d specifiers appear in
--- this file.  Translators need only reorder %s tokens to fit their language.
---
--- To add a new locale, copy this file to lang/<code>.lua, translate every
--- value, and add the new file to incha.txt BEFORE core/Lang.lua.

local M = {}


-- ── Common fallback labels ───────────────────────────────────────────────────

M.common_ready              = "ready"
M.common_soon               = "soon!"
M.common_now                = "NOW"
M.common_up                 = "up!"
M.common_imminent           = "imminent"
M.common_interrupt          = "INTERRUPT!"
M.common_you                = "YOU"
M.common_inc                = "INC"   -- "incoming": appended to a timer label when its countdown has elapsed

-- ── Sunspire (SS) ── SunspireCommon.lua ─────────────────────────────────────

M.ss_block_heavy_attack     = "Block! (Heavy Attack)"
M.ss_block_jump             = "Block! (Jump)"
M.ss_dodge_leap             = "Dodge! (Leap)"
M.ss_block_shield_charge    = "Block! (Shield Charge)"
M.ss_dodge_breath           = "Dodge! (Breath)"
M.ss_atro_incoming          = "Atro incoming! (Spit)"

-- SS shared tracker-row labels.  These are event names shown in the name column
-- of the Event Tracker; the ETA countdown is displayed separately.
M.ss_landing                = "Landing"
M.ss_can_fly_in             = "Can Fly In: "

-- ── Sunspire ── Lokke ────────────────────────────────────────────────────────

M.ss_lokke_block_glacial    = "Block! (Glacial Fist)"
M.ss_lokke_laser            = "Laser"
-- Tracker labels for the three Ice Tomb rotation positions.
M.ss_lokke_tomb_name_1      = "Ice Tomb 1"
M.ss_lokke_tomb_name_2      = "Ice Tomb 2"
M.ss_lokke_tomb_name_3      = "Ice Tomb 3"
-- Slot-state labels shown inside each active tomb row.
M.ss_lokke_tomb_slot_a      = "[A] "
M.ss_lokke_tomb_slot_b      = "[B] "
M.ss_lokke_tomb_take        = "Take"
M.ss_lokke_tomb_heal        = "Heal"
M.ss_lokke_tomb_done        = "Done"
M.ss_lokke_tomb_inc         = "inc"
M.ss_lokke_tomb_double      = "Double"

-- ── Sunspire ── Yolna ────────────────────────────────────────────────────────

M.ss_yolna_kill_atro        = "Kill Atro!"
M.ss_yolna_dodge_geyser     = "Dodge! (Geyser)"
M.ss_yolna_next_flare       = "Next Flare"
M.ss_yolna_cataclysm_ends   = "Cataclysm"

-- ── Sunspire ── Nahvii ───────────────────────────────────────────────────────

M.ss_nahvii_you_meteor      = "YOU → Meteor!"
M.ss_nahvii_block_slam      = "Block! (Slam)"
M.ss_nahvii_block_stonefist = "Block! (Stonefist)"
M.ss_nahvii_sweep_right     = "> Sweep Breath >>>"
M.ss_nahvii_sweep_left      = "<<< Sweep Breath <"
M.ss_nahvii_soul_tear       = "SOUL TEAR!"
M.ss_nahvii_dodge_negate    = "Dodge! (Negate)"
M.ss_nahvii_next_meteor     = "Meteor"
M.ss_nahvii_interrupt_in    = "Interrupt"
M.ss_nahvii_next_pins       = "Pins"
-- portal_urgent shows when the player must already be inside (>11 s remaining);
-- portal shows the plain countdown.  Different labels so the urgency reads clearly.
M.ss_nahvii_portal_urgent   = "ENTER PORTAL"
M.ss_nahvii_portal          = "Portal"
M.ss_nahvii_fire_storm_begin = "Storm Start"
M.ss_nahvii_fire_storm_end  = "Storm End"
M.ss_nahvii_portal_wipe     = "Portal Wipe"

-- ── Rockgrove (RG) ── RockgroveCommon.lua ───────────────────────────────────

M.rg_block_sundering        = "Block! (Sundering)"
M.rg_dodge_scalding         = "Dodge! (Scalding)"

-- ── Rockgrove ── Oaxiltso ────────────────────────────────────────────────────

M.rg_oaxiltso_dodge_cone    = "Dodge! (Cone)"
M.rg_oaxiltso_add_spawning  = "ADD SPAWNING!"
M.rg_oaxiltso_next_blitz    = "Next Blitz"
M.rg_oaxiltso_next_sludge   = "Next Sludge"
M.rg_oaxiltso_boss_add_enrage = "BOSS + ADD ENRAGED"
M.rg_oaxiltso_boss_enraged  = "BOSS ENRAGED"
M.rg_oaxiltso_add_enraged   = "ADD ENRAGED"

-- ── Rockgrove ── Bahsei ──────────────────────────────────────────────────────

M.rg_bahsei_next_curse      = "Next Curse"
M.rg_bahsei_portal          = "Portal"
M.rg_bahsei_portal_cw       = "CW"
M.rg_bahsei_portal_ccw      = "CCW"
M.rg_bahsei_portal_progress = "in progress"
M.rg_bahsei_tank_exploding  = "TANK EXPLODING!"
M.rg_bahsei_death_touch     = "Death Touch"
M.rg_bahsei_no_portal       = "No Portal"
M.rg_bahsei_next_sickle     = "Next Sickle"

-- ── Rockgrove ── Xalvakka ────────────────────────────────────────────────────

M.rg_xalvakka_next_jump     = "Next Jump"
M.rg_xalvakka_soul_res      = "Soul Resonance"
M.rg_xalvakka_manifold      = "Manifold: "
M.rg_xalvakka_shield        = "Shield: "
M.rg_xalvakka_run_in        = "RUN IN: "
M.rg_xalvakka_on_blob       = "ON BLOB  -  stand still!"

-- ── Dreadsail Reef (DSR) ── Lylanar ─────────────────────────────────────────

M.dsr_lylanar_dodge_cleave  = "Dodge! (Cleave)"
-- Ember/bubble suffix: pick singular vs plural in Lua based on stack count
M.dsr_lylanar_ember_suffix  = "  -  %s stack"
M.dsr_lylanar_ember_suffix_p = "  -  %s stacks"
M.dsr_lylanar_drop          = "DROP!"
M.dsr_lylanar_fire_fragility = "Fire Fragility"
M.dsr_lylanar_ice_fragility = "Ice Fragility"
M.dsr_lylanar_need_fire_dome = "Need Fire Dome"
M.dsr_lylanar_need_ice_dome = "Need Ice Dome"
M.dsr_lylanar_axe           = "Axe"
M.dsr_lylanar_sword         = "  Sword: "   -- trailing space; concat Fmt.timer() at call site
M.dsr_lylanar_imm_blister   = "Imminent Blister"
M.dsr_lylanar_imm_chill     = "Imminent Chill"

-- ── Dreadsail Reef ── ReefGuardian ──────────────────────────────────────────

M.dsr_reef_elec_cleansed    = "⚡ CLEANSED"
M.dsr_reef_poison_cleansed  = "☣ CLEANSED"
-- Stack labels: color and urgency suffix are built in Lua
M.dsr_reef_elec_label       = "⚡ "
M.dsr_reef_poison_label     = "☣ "
M.dsr_reef_stack            = "%s stack"
M.dsr_reef_stack_p          = "%s stacks"
M.dsr_reef_reef_timer       = "Reef %s"     -- idx via Lang.t(key, idx); ETA in tracker column
M.dsr_reef_acidic_vuln      = "Acidic Vuln"

-- ── Dreadsail Reef ── Taleria ────────────────────────────────────────────────

M.dsr_taleria_dodge_maelstrom = "DODGE! (Maelstrom ends)"
M.dsr_taleria_heal          = "HEAL!"
M.dsr_taleria_maelstrom     = "Maelstrom"
M.dsr_taleria_behemoth_slam = "Behemoth SLAM"
M.dsr_taleria_behemoth      = "Behemoth"
M.dsr_taleria_storm_cw      = "Storm CW →"
M.dsr_taleria_storm_ccw     = "Storm CCW ←"
-- Bridge: label abbreviations + next threshold
M.dsr_taleria_bridge_label_1 = "G"
M.dsr_taleria_bridge_label_2 = "Y"
M.dsr_taleria_bridge_label_3 = "Pu"
M.dsr_taleria_next_bridge   = "Next bridge: "  -- trailing space; concat Fmt.pct() at call site
-- Alerts
M.dsr_taleria_maelstrom_alert = "Maelstrom  -  HEAL! (6 s)"
M.dsr_taleria_portal_green  = "Green portal open  -  60 s!"
M.dsr_taleria_portal_yellow = "Yellow portal open  -  60 s!"
M.dsr_taleria_portal_purple = "Purple portal open  -  60 s!"

-- ── Kyne's Aegis (KA) ── Yandir ─────────────────────────────────────────────
-- KA uses location-based detection; no boss name keys needed.

M.ka_yandir_kill_poison_totem   = "Kill! (Poison Totem)"
M.ka_yandir_stand_still_poison  = "Stand Still! (Poison)"
M.ka_yandir_block_gargoyle      = "Block! (Gargoyle Totem)"
M.ka_yandir_casts_healing       = "Yandir Healing"
M.ka_yandir_jump_block          = "Block! (Yandir Jump)"
M.ka_yandir_dodge_sea_adder     = "Dodge! (Sea Adder)"
M.ka_yandir_block_cleave        = "Block! (Toxic Tide)"
M.ka_yandir_block_uppercut      = "Block! (Uppercut)"
M.ka_yandir_block_shatter       = "Block! (Sundering Strike)"
M.ka_yandir_kill_harpy_totem    = "Kill! (Harpy Totem)"
M.ka_yandir_kill_dragon_totem   = "Kill! (Dragon Totem)"
M.ka_yandir_kill_gargoyle_spwn  = "Kill! (Gargoyle Totem)"
-- Tracker row labels
M.ka_yandir_totem_label     = "Totem"
M.ka_yandir_gryphon_label   = "Gryphon"
M.ka_yandir_gryphon_skip    = "Skip!"
M.ka_yandir_gryphon_early   = " (%s early)"
M.ka_yandir_gryphon_fail    = "Fail @ "

-- ── Kyne's Aegis ── Vrol ─────────────────────────────────────────────────────

M.ka_vrol_kill_conjurer     = "Kill! (Conjurer)"
M.ka_vrol_kill_conjurer_20s = "Kill! (Conjurer)"
M.ka_vrol_dodge_fog         = "Dodge! (Fog)"
M.ka_vrol_kill_harpoon      = "Kill! (Harpoon)"
M.ka_vrol_harpoon_action    = "Harpoon!"
M.ka_vrol_interrupt_apoth   = "Interrupt! (Apothecary)"
M.ka_vrol_portal_ok         = "Portal OK!"
M.ka_vrol_portal_failed     = "Portal Failed!"
-- Tracker row labels
M.ka_vrol_fog_clears        = "Fog Clears"
M.ka_vrol_next_fog          = "Next Fog"
M.ka_vrol_conduit           = "Conduit"
M.ka_vrol_portal_label      = "Portal"

-- ── Kyne's Aegis ── Falgravn ─────────────────────────────────────────────────

-- Tracker row labels
M.ka_falgravn_instability   = "Instability"
M.ka_falgravn_blood_ball    = "Blood Ball"
M.ka_falgravn_open_gates    = "Open Gates"
M.ka_falgravn_torturer_tp   = "Torturer TP"
M.ka_falgravn_hm_suffix     = " [HM: ON]"
-- Action strings
M.ka_falgravn_interrupt_inf     = "Interrupt! (Infuser)"
M.ka_falgravn_inf_buff          = "Infuser Buff passed!"
M.ka_falgravn_move              = "Move!"
M.ka_falgravn_block_cast        = "Block! (Bloody Frenzy)"
M.ka_falgravn_dodge             = "Dodge! (Blood Cleave)"
M.ka_falgravn_block_fountain    = "Block! (Blood Fountain)"
M.ka_falgravn_open_gates_action = "Open the Gates!"
M.ka_falgravn_kill_torturer     = "Kill! (Torturer)"
M.ka_falgravn_torturer_down     = "Torturer Comes Down!"
M.ka_falgravn_dodge_torturer    = "Dodge! (Torturer LA)"
M.ka_falgravn_torturer_la_label = "Torturer LA's"
M.ka_falgravn_kill_prison       = "Kill! (Prison)"
M.ka_falgravn_prisoner_warn     = "Kill! (Torturer) — %s fed %s× (dying!)"   -- %s=prisoner name, %s=stack count

-- ── Asylum Sanctorium (AS) ── OlmsEncounter ─────────────────────────────────

M.as_olms_kite_storm        = "Kite! (Storm the Heavens)"
M.as_olms_steam_breath      = "Steam Breath! Move!"
M.as_olms_charges           = "Charges!"
M.as_olms_trial_by_fire     = "Trial by Fire!"
M.as_olms_jump_dodge        = "Jump! Dodge!"
M.as_olms_blast_target      = "Blast! → %s"
M.as_olms_blast_bar         = "Blast → %s"
M.as_olms_interrupt_llothis = "Interrupt Llothis!"
M.as_olms_strike_target     = "Strike! → %s"
M.as_olms_strike_bar        = "Strike → %s"
M.as_olms_kill_protector    = "Kill the Protector!"
M.as_olms_shield_down       = "Shield down!"
M.as_olms_protector_active  = "[!] PROTECTOR ACTIVE"
-- Tracker row labels (name column; ETA column handled by setRow)
M.as_olms_storm_label       = "Storm"
M.as_olms_steam_label       = "Steam"
M.as_olms_charges_label     = "Charges"
M.as_olms_fire_label        = "Fire"
M.as_olms_llothis_dormant   = "Llothis DORMANT"
M.as_olms_blast_label       = "Blast"
M.as_olms_bolts_label       = "Bolts"
M.as_olms_felms_dormant     = "Felms DORMANT"
M.as_olms_strike_label      = "Strike"
-- %s receives a threshold integer from tostring()
M.as_olms_jump_at           = "Jump at %s%%!"
M.as_olms_storm_soon        = "Storm soon!"

-- ── Cloudrest (CR) ── ZmajaEncounter ────────────────────────────────────────

-- Info labels

-- ── Sanity's Edge (SE) ── YaseylaEncounter ───────────────────────────────────

M.se_yaseyla_frost_bomb_you = "Frost Bomb on you! Drop it!"
M.se_yaseyla_frost_bomb_tgt = "Frost Bomb -> %s"
M.se_yaseyla_fire_bombs_tgt = "Fire Bombs -> %s"
M.se_yaseyla_chains         = "Chains!"
M.se_yaseyla_ignite         = "Ignite on you! Move!"
M.se_yaseyla_shrapnel_you   = "SHRAPNEL! Stack! (%s)"
M.se_yaseyla_shrapnel       = "Shrapnel! Stack!"
M.se_yaseyla_knife_blast    = "Knife Blast -> %s"
M.se_yaseyla_vengeful_strike = "Vengeful Strike! Dodge!"
M.se_yaseyla_portal         = "Portal! Vanton's Clarity"
M.se_yaseyla_enrage         = "ENRAGE! Seethe!"
M.se_yaseyla_headbutt       = "Headbutt -> %s! DODGE!"
M.se_yaseyla_overwhelming   = "Overwhelming Lightning on you!"
M.se_yaseyla_execute        = "Execute! (<26%%) Fire Bombs accelerate"
-- CA bar labels
M.se_yaseyla_fire_bombs_bar    = "Fire Bombs!"
M.se_yaseyla_knife_blast_bar   = "Knife Blast → %s"
M.se_yaseyla_charge_bar        = "Charge → %s"
-- CA alert popups
M.se_yaseyla_frost_bomb_alert  = "FROST BOMB - drop!"
M.se_yaseyla_deflect_alert     = "STACK!"
M.se_yaseyla_shrapnel_alert    = "SHRAPNEL - STACK!"
M.se_yaseyla_vengeful_alert    = "VENGEFUL STRIKE"
M.se_yaseyla_portal_alert      = "PORTAL - synergy!"
M.se_yaseyla_enrage_alert      = "ENRAGE!"
M.se_yaseyla_headbutt_alert    = "HEADBUTT - DODGE!"
M.se_yaseyla_ovw_lightning     = "OVW LIGHTNING"
M.se_yaseyla_portal_pct_alert  = "PORTAL PHASE ~%s%%"
-- HP milestone action strings
M.se_yaseyla_90pct          = "90%% - Wamasu + Archers incoming!"
M.se_yaseyla_80pct          = "80%% - Shrapnel incoming!"
M.se_yaseyla_70pct          = "70%% - Wamasu + Archers incoming!"
M.se_yaseyla_60pct          = "60%% - Portal phase!"
M.se_yaseyla_55pct          = "55%% - Shrapnel incoming!"
M.se_yaseyla_50pct          = "50%% - Wamasu + Archers incoming!"
M.se_yaseyla_35pct          = "35%% - Portal phase!"
M.se_yaseyla_30pct          = "30%% - Wamasu + Archers incoming!"
M.se_yaseyla_25pct          = "25%% - Shrapnel incoming!"
M.se_yaseyla_20pct          = "20%% - Wamasu + Archers + Shrapnel!"
M.se_yaseyla_10pct          = "10%% - Wamasu + Archers + Shrapnel!"
-- Info labels
M.se_yaseyla_fire_bombs_first  = "Fire Bombs: first ~7s"
M.se_yaseyla_fire_bombs_name   = "Fire Bombs"
M.se_yaseyla_bombs_exec_name   = "Bombs (exec)"
M.se_yaseyla_frost_first       = "Frost: first ~17s"
M.se_yaseyla_frost_bomb_label  = "Frost Bomb"
M.se_yaseyla_chains_label      = "Chains"

-- ── Sanity's Edge ── AnsuulEncounter ─────────────────────────────────────────

M.se_ansuul_triplet_header  = "TRIPLET PHASE!"
M.se_ansuul_triplet_ended   = "Triplet ended!"
M.se_ansuul_calamity_stack  = "Calamity! Stack!"
M.se_ansuul_kite_wrack      = "Kite! Wrack incoming!"
M.se_ansuul_interrupt_exec  = "INTERRUPT! Execute!"
M.se_ansuul_sunburst        = "Sunburst on you! Dodge!"
M.se_ansuul_poisoned_mind   = "Poisoned Mind on you!"
M.se_ansuul_manic_phobia    = "Manic Phobia -> %s"
M.se_ansuul_interrupt_inf   = "INTERRUPT! Enraged Inferno!"
M.se_ansuul_enraged_flare   = "Enraged Flare -> %s"
M.se_ansuul_maze_header     = "Maze phase!"
M.se_ansuul_maze_cleared    = "Maze cleared! Calamity in ~9s"
-- CA bar labels
M.se_ansuul_sunburst_bar    = "SUNBURST"
M.se_ansuul_wrathstorm_bar  = "Wrathstorm!"
-- CA alert popups
M.se_ansuul_kite_alert      = "KITE!"
M.se_ansuul_manic_alert     = "MANIC PHOBIA - fear!"
M.se_ansuul_inferno_alert   = "INTERRUPT - Inferno!"
M.se_ansuul_flare_alert     = "ENRAGED FLARE"
-- Info strings
M.se_ansuul_maze_no_cal     = "Maze phase (no Calamity)"
M.se_ansuul_triplet_cal     = "TRIPLET - Calamity"
M.se_ansuul_calamity_first  = "Calamity: first ~9s"
M.se_ansuul_calamity_label  = "Calamity"
M.se_ansuul_split_phase     = "Split phase - equalize HP!"
M.se_ansuul_navigate_maze   = "Navigate the maze"
M.se_ansuul_now             = "now!"

-- ── Sanity's Edge ── ChimeraEncounter ────────────────────────────────────────

M.se_chimera_header         = "Chimera spawned!"
M.se_chimera_despawning     = "Chimera despawning..."
M.se_chimera_chain_lightning = "Chain Lightning!"
M.se_chimera_chain_circuit  = "Chain Circuit on you!"
M.se_chimera_arctic_shred   = "Arctic Shred -> %s"
M.se_chimera_lion_double    = "Lion Double Strike!"
M.se_chimera_gryphon_peck   = "Gryphon Peck!"
M.se_chimera_lightning_bolt = "Lightning Bolt -> %s"
M.se_chimera_wind_lance     = "Wind Lance! Move!"
-- CA alert popups
M.se_chimera_chain_lightning_alert = "CHAIN LIGHTNING"
M.se_chimera_chain_circuit_alert   = "CHAIN CIRCUIT"
M.se_chimera_wind_lance_alert      = "WIND LANCE"
-- CA bar labels
M.se_chimera_arctic_shred_bar = "Arctic Shred!"
M.se_chimera_lion_double_bar  = "Lion Double Strike!"
M.se_chimera_gryphon_peck_bar = "Gryphon Peck!"
M.se_chimera_bolt_bar         = "Bolt!"
-- Portal mantle labels
M.se_chimera_portal_wamasu  = "Wamasu Portal (Green)"
M.se_chimera_portal_lion    = "Lion Portal (Red)"
M.se_chimera_portal_gryphon = "Gryphon Portal (Blue)"
-- Info labels
M.se_chimera_despawn_label  = "Despawn"
M.se_chimera_chain_label    = "Chain Ltng"

-- ── Lucent Citadel (LC) ── LCCommon.lua ──────────────────────────────────────

M.lc_swap_hindered          = "SWAP! (Hindered)"
M.lc_hindered_alert         = "Tank swap — Hindered!"
M.lc_conv_tether_soon       = "Tethers incoming — pick partners!"
M.lc_conv_weakening_charge  = "Weakening Charge → %s"
M.lc_conv_weakening_you     = "YOU"

-- ── Lucent Citadel ── RyelazEncounter ────────────────────────────────────────

M.lc_ryelaz_brilliant       = "Brilliant Annihilation!"
M.lc_ryelaz_bleak           = "Bleak Annihilation!"
M.lc_ryelaz_annihil_action  = "STACK — Annihilation!"
M.lc_ryelaz_side_dark       = "Ryelaz side (dark)"
M.lc_ryelaz_side_light      = "Zilyesset side (light)"
M.lc_ryelaz_add_light       = "Kill Lightweaver! (light side add)"
M.lc_ryelaz_add_dark        = "Kill Blackguard! (dark side add)"

-- ── Lucent Citadel ── DarielEncounter ────────────────────────────────────────

M.lc_dariel_throw_you       = "Powerful Throw on YOU!"
M.lc_dariel_throw_target    = "Powerful Throw → %s"

-- ── Lucent Citadel ── OrphicEncounter ────────────────────────────────────────

M.lc_orphic_thunder_thrall       = "Thunder Thrall (Xoryn jump)"
M.lc_orphic_lightning_flood      = "Lightning Flood → %s"
M.lc_orphic_break_crystal        = "Break out of the crystal!"
M.lc_orphic_break_out_bar        = "BREAK OUT!"
M.lc_orphic_shield_throw         = "Shield Throw → %s"
M.lc_orphic_color_change         = "Color change! Switch mirror!"
M.lc_orphic_color_change_alert   = "Color Change!"
-- Info labels
M.lc_orphic_thrall_first    = "Thrall: first ~8s"
M.lc_orphic_thrall_label    = "Thrall"
M.lc_orphic_flood_first     = "Flood:  first ~3s"
M.lc_orphic_flood_label     = "Flood"

-- ── Lucent Citadel ── XynizataEncounter ──────────────────────────────────────

M.lc_xynizata_interrupt_beam = "INTERRUPT — Piercing Beam!"
M.lc_xynizata_beam_bar       = "INTERRUPT — Beam!"
M.lc_xynizata_interrupt_vitr = "INTERRUPT — Vitrify!"
-- Info labels
M.lc_xynizata_beam_first    = "Beam: first ~14s"
M.lc_xynizata_beam_label    = "Beam"
M.lc_xynizata_vitr_first    = "Vitrify: first ~9s"
M.lc_xynizata_vitr_label    = "Vitrify"

-- ── Lucent Citadel ── XorynEncounter ─────────────────────────────────────────

M.lc_xoryn_accel_charge     = "Accelerating Charge → Chain Lightning!"
M.lc_xoryn_tempest          = "Tempest! MOVE from mirror line!"
M.lc_xoryn_atronach_aoe     = "Atronach AOE on YOU!"
M.lc_xoryn_lustrous_javelin = "Lustrous Javelin on you!"
M.lc_xoryn_arcane_knot      = "Arcane Knot — carry and pass!"
M.lc_xoryn_tether           = "Tether on you! Separate from partner!"
M.lc_xoryn_tethers_cast    = "Tethers!"
M.lc_xoryn_fluctuating      = "Fluctuating Current — hold, then drop!"
M.lc_xoryn_overloaded       = "Overloaded — DROP the current!"
-- CA bar labels
M.lc_xoryn_barrage_bar      = "Necrotic Barrage!"
M.lc_xoryn_tempest_bar      = "MOVE from line!"
M.lc_xoryn_atronach_bar     = "Atronach AOE → %s"
-- CA alert popups
M.lc_xoryn_chain_lightning  = "Chain Lightning incoming!"
M.lc_xoryn_javelin_alert    = "Javelin on YOU!"
M.lc_xoryn_knot_alert       = "Carry knot! Pass it!"
M.lc_xoryn_knot_carrier    = "Knot: %s"
M.lc_xoryn_tether_alert     = "TETHER! Move away!"
M.lc_xoryn_current_alert    = "Hold current! Drop at edge!"
M.lc_xoryn_drop_alert       = "DROP current!"
-- Info
M.lc_xoryn_current          = "Current"
M.lc_xoryn_drop_now         = "DROP NOW!"

-- ── Ossein Cage (OC) ── OsseinCageCommon.lua ─────────────────────────────────

M.oc_carrion_label          = "Carrion: %s"
M.oc_carrion_alert          = "Carrion: %s stacks!"
M.oc_move_life_drain        = "Move! (Life Drain)"
M.oc_life_drain_alert       = "Life Drain"
M.oc_swap_hindered          = "SWAP! (Hindered)"
M.oc_hindered_swap_alert    = "Hindered  -  SWAP!"
M.oc_toxic_ire              = "Toxic Ire (you!)"
M.oc_toxic_ire_alert        = "Toxic Ire"
M.oc_detonate_soul          = "Detonate Soul (you!)"
M.oc_detonate_soul_bar      = "Detonate Soul"

-- ── Ossein Cage ── JynorahEncounter ──────────────────────────────────────────

M.oc_jynorah_titanic_leap   = "Titanic Leap!"
M.oc_jynorah_reflective     = "Reflective Scales  -  stop DPS!"
M.oc_jynorah_titanic_clash  = "Titanic Clash (~37.5s)"
M.oc_jynorah_clash_bar      = "TITANIC CLASH! DODGE!"
M.oc_jynorah_valneer_hit    = "Valneer hit!"
M.oc_jynorah_myrinax_hit    = "Myrinax hit!"
M.oc_jynorah_sparking_you   = "Sparking Curse  -  on YOU!"
M.oc_jynorah_sparking_tgt   = "Sparking Curse -> %s"
M.oc_jynorah_blazing_you    = "Blazing Curse  -  on YOU!"
M.oc_jynorah_blazing_tgt    = "Blazing Curse -> %s"
M.oc_jynorah_sparking_valneer = "Sparking Curse  -  swap to Valneer side!"
M.oc_jynorah_blazing_myrinax = "Blazing Curse  -  swap to Myrinax side!"
M.oc_jynorah_sparking_blue  = "Sparking Curse  -  BLUE!"
M.oc_jynorah_blazing_red    = "Blazing Curse  -  RED!"
M.oc_jynorah_curse_alert    = "Curse incoming!"
M.oc_jynorah_coldflame      = "Coldflame Surge on you! MOVE!"
M.oc_jynorah_brimstone      = "Brimstone Surge on you! MOVE!"
M.oc_jynorah_surge_alert    = "Surge on YOU!"
M.oc_jynorah_stomp_bar      = "DODGE  -  stomp!"
M.oc_jynorah_heat_ray       = "Heat Ray on you  -  move!"
M.oc_jynorah_heat_ray_alert = "Heat Ray on YOU!"
M.oc_jynorah_myrinax_breath = "Myrinax Breath on you! MOVE!"
M.oc_jynorah_valneer_breath = "Valneer Breath on you! MOVE!"
M.oc_jynorah_breath_alert   = "BREATH  -  MOVE!"
M.oc_jynorah_tail_slam_bar  = "Tail Slam → %s"
-- Info
M.oc_jynorah_clash_timer    = "CLASH"
M.oc_jynorah_leap_first     = "Leap: first ~5s"
M.oc_jynorah_leap_label     = "Leap"

-- ── Ossein Cage ── KazpianEncounter ──────────────────────────────────────────

M.oc_kazpian_chains         = "Chains: %s → %s"
M.oc_kazpian_chained_alert  = "CHAINED — pull apart!"
M.oc_kazpian_biting_blaze   = "Biting Blaze → %s"
M.oc_kazpian_vile_leap      = "Vile Leap!"
M.oc_kazpian_seething_leap  = "Seething Vile Leap!"
M.oc_kazpian_seething_bar   = "VILE LEAP (enrage)!"
M.oc_kazpian_agonizer       = "Agonizer Bombs!"
M.oc_kazpian_giant_sword_bar = "Giant Sword!"
M.oc_kazpian_dodge_cones    = "Dodge cones!"
M.oc_kazpian_dodge_spear    = "Dodge spear!"
M.oc_kazpian_storm_slam     = "Molag Kena Storm Slam — DODGE!"
M.oc_kazpian_storm_slam_bar = "DODGE — Storm Slam!"
M.oc_kazpian_storm_surge_bar = "Storm Surge!"
M.oc_kazpian_heavy_shock    = "Molag Kena Heavy Shock on you!"
M.oc_kazpian_heavy_shock_alert = "Heavy Shock on YOU!"
M.oc_kazpian_immolating     = "Immolating Sphere on you!"
M.oc_kazpian_immolating_alert = "Immolating Sphere!"
M.oc_kazpian_portal_phase   = "Portal phase %s!"
M.oc_kazpian_stricken       = "Stricken — tank mechanic!"
M.oc_kazpian_stricken_alert = "Stricken on YOU!"
M.oc_kazpian_firebomb       = "Firebomb — spread!"
M.oc_kazpian_firebomb_alert = "Firebomb on YOU!"
M.oc_kazpian_tort_chains    = "Tortuous Chains — run from Kazpian!"
M.oc_kazpian_channeler_down = "Channeler down! (%s dead)"
-- Info
M.oc_kazpian_portal_label   = "Portal: phase %s"
M.oc_kazpian_channelers     = "Channelers dead: %s"

-- ── Ossein Cage ── ShaperEncounter ───────────────────────────────────────────

M.oc_shaper_ogrim_you        = "Ogrim Charge on YOU! Move!"
M.oc_shaper_ogrim_tgt        = "Ogrim Charge → %s"
M.oc_shaper_ogrim_bar        = "MOVE — Ogrim Charge!"
M.oc_shaper_shielded_kill    = "Shaper of Flesh shielded — kill channelers!"
M.oc_shaper_shielded_alert   = "Shaper shielded — kill channelers!"
M.oc_shaper_vulnerable       = "Shaper vulnerable — BURN!"
M.oc_shaper_vulnerable_alert = "Shaper vulnerable!"
M.oc_shaper_channelers_shld  = "Channelers shielding Shaper — eliminate them!"
M.oc_shaper_shielded_info    = "Shaper: SHIELDED"

-- ── Cloudrest (CR) ── ZmajaEncounter (current implementation) ────────────────

-- Z'Maja abilities
M.cr_zmaja_jump              = "Z'Maja jumping!"
M.cr_zmaja_hide_jump         = "Z'Maja retreating to shadow!"
M.cr_zmaja_crushing_dark     = "Kite! Crushing Darkness"
M.cr_zmaja_crushing_kite     = "KITE!"
M.cr_zmaja_shadow_splash     = "Shadow Splash! Interrupt!"
M.cr_zmaja_shadow_splash_bar = "INTERRUPT! Shadow Splash"
M.cr_zmaja_baneful_mark      = "Baneful Mark! (execute)"
M.cr_zmaja_baneful_alert     = "BANEFUL MARK"
M.cr_zmaja_portal_reset      = "Z'Maja re-engaged — portal counter reset"
-- Malevolent Cores
M.cr_zmaja_core_exposed      = "Core exposed!"
M.cr_zmaja_core_out_alert    = "Core out! Pick it up!"
M.cr_zmaja_core_out_ca       = "CORE OUT!"
M.cr_zmaja_core_missed       = "Core missed!"
M.cr_zmaja_core_missed_alert = "Core MISSED!"
M.cr_zmaja_core_missed_ca    = "CORE MISSED!"
M.cr_zmaja_core_picked       = "Core picked up."
-- Portal
M.cr_zmaja_shadow_realm      = "Shadow Realm — Group %s"
-- Siroria
M.cr_zmaja_siro_flare        = "Flare → %s"
M.cr_zmaja_siro_ha           = "Siroria HA! (%s)"
M.cr_zmaja_siro_ha_bar       = "Siro HA!"
M.cr_zmaja_siro_jump         = "Siroria jumping!"
M.cr_zmaja_siro_banner       = "Siroria Banner!"
M.cr_zmaja_siro_root         = "Rooted! (Siroria)"
-- Relequen
M.cr_zmaja_rele_ha           = "Relequen HA! (%s)"
M.cr_zmaja_rele_ha_bar       = "Rele HA!"
M.cr_zmaja_rele_jump         = "Relequen jumping!"
M.cr_zmaja_rele_interrupt    = "Interrupt Relequen!"
M.cr_zmaja_rele_jolt         = "Relequen Jolt! Move!"
M.cr_zmaja_rele_overload_in  = "Overload incoming — bar swap!"
M.cr_zmaja_rele_overload_you = "Overload on you — swap now!"
M.cr_zmaja_rele_bar_swap     = "BAR SWAP"
-- Galenwe
M.cr_zmaja_gale_ha           = "Galenwe HA! (%s)"
M.cr_zmaja_gale_ha_bar       = "Gale HA!"
M.cr_zmaja_gale_jump         = "Galenwe jumping!"
M.cr_zmaja_gale_interrupt    = "Interrupt Galenwe!"
M.cr_zmaja_gale_donut        = "Galenwe Donut! Out!"
M.cr_zmaja_gale_frost_you    = "Frost! Drop in 6s"
M.cr_zmaja_gale_frost_alert  = "FROST — drop in 6s"
M.cr_zmaja_gale_frost_tgt    = "Frost → %s"
M.cr_zmaja_gale_drop_frost   = "Drop frost now!"
M.cr_zmaja_gale_drop_alert   = "DROP FROST!"
M.cr_zmaja_gale_comet        = "Chilling Comet! Move!"
M.cr_zmaja_gale_comet_alert  = "COMET — move!"
-- Environment
M.cr_zmaja_creeper_root      = "Rooted! (Creeper)"
M.cr_zmaja_olorime_spear     = "Spear → %s (%s)"
-- Info labels
M.cr_zmaja_portal_open_label = "Portal open"
M.cr_zmaja_portal_closing    = "closing"
M.cr_zmaja_portal_next_label = "Next portal"
M.cr_zmaja_execute_phase     = "!!! EXECUTE PHASE !!!"
M.cr_zmaja_shadow_group      = "Shadow Group %s"
M.cr_zmaja_spears_label      = "Spears: "
M.cr_zmaja_siro_label        = "Siro: Jump %s  Bnr %s"
M.cr_zmaja_rele_label        = "Rele: Jump %s  Bash %s"
M.cr_zmaja_gale_label        = "Gale: Jump %s  Bash %s"
M.cr_zmaja_bash_due          = "INTERRUPT"

package.loaded["lang.en"] = M
return M
