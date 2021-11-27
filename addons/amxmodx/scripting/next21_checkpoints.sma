#include <amxmodx>
#include <amxmisc>
#include <fakemeta_util>
#include <reapi>

new const PLUGIN[] = "Checkpoints"
new const VERSION[] = "0.85"
new const AUTHOR[] = "Psycrow"

new const MODEL_CHECKPOINT[] = "models/next21_deathrun/checkpoint.mdl"
new const SOUND_CHECKPOINT[] = "next21_deathrun/checkpoint.wav"

new const CLASSNAME_CHECKPOINT[] = "next21_checkpoint"

#define MAX_CHECKPOINTS				32
#define TASK_RETURN_PLAYER			100

#define RETURN_PLAYER_TRY_TIMES		10

#define CHECKPOINT_RADIUS			45.0
#define CHECKPOINT_COLORMAP_DELAY	0.05

#define DHUD_POSITION 		0, 255, 0, -1.0, 0.8, 2, 1.05, 1.05, 0.05, 3.0

new const CHAT_PREFIX[] = "^3[Checkpoints]"
#define ACCESS_FLAG			ADMIN_MAP
#define COLOR_EFFECT 		// color transition effect in checkpoints
//#define DUELS_ENABLED 	// for https://github.com/Mistrick/DeathrunMod

#if defined DUELS_ENABLED
#include <deathrun_duel>
#endif

enum _:CvarList
{
	CVAR_CHECKPOINT_REWARD,				// common reward, 0 - none
	CVAR_CHECKPOINT_MUL,				// common reward multiplier
	CVAR_CHECKPOINT_FINISH_REWARD[3],	// rewards for finish, 0 - none
	CVAR_CHECKPOINT_TELEPORT,			// teleport after spawn
	CVAR_CHECKPOINT_LIGHT,				// 0 - none, 1 - light
	Float: CVAR_CHECKPOINT_GLOW,		// glow size
	CVAR_CHECKPOINT_SKIP_LIMIT			// the number of checkpoints that can't be skipped
}

enum _:CheckpointBodies
{
	CP_BODY_NORMAL,
	CP_BODY_FINISH
}

enum _:CheckpointSkins
{
	CP_SKIN_NORMAL,
	CP_SKIN_FINISH
}

enum _:CheckpointMenuItems
{
	MENU_ITEM_CP_SPAWN,
	MENU_ITEM_CP_REMOVE,
	MENU_ITEM_CP_REMOVEALL,
	MENU_ITEM_CP_SAVE
}

new
	g_iCheckpointsNum,
	g_iCheckpoint[MAX_CHECKPOINTS],
	g_iMenuEditor,
	bool: g_bWasChanged,
	g_iRoundEnd,
	g_iPlrCompleted[MAX_PLAYERS + 1],
	g_iFinishedNum,
	#if defined DUELS_ENABLED
	bool: g_bDuelStarted,
	#endif
	g_pCvars[CvarList]


public plugin_precache()
{
	precache_model(MODEL_CHECKPOINT)
	precache_sound(SOUND_CHECKPOINT)
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	register_clcmd("checkpoint", "clcmd_checkpoint_menu", ACCESS_FLAG, "-Open Checkpoint Editor Menu")
	register_clcmd("say /checkpoint", "clcmd_checkpoint_menu", ACCESS_FLAG, "-Open Checkpoint Editor Menu")
	register_clcmd("say_team /checkpoint", "clcmd_checkpoint_menu", ACCESS_FLAG, "-Open Checkpoint Editor Menu")
	
	AddMenuItem("Checkpoints Menu", "checkpoint", ACCESS_FLAG, PLUGIN)
	
	register_dictionary("next21_checkpoints.txt")
		
	register_cvars()
	load_checkpoints()
	g_iMenuEditor = create_menu_editor()
}

/*** Checkpoints functions ***/

load_checkpoints()
{
	new szMap[48]
	get_mapname(szMap, charsmax(szMap))
	add(szMap, charsmax(szMap), ".ini")
	
	new szDirCfg[128], iDir, szFile[128]
	get_configsdir(szDirCfg, charsmax(szDirCfg))
	add(szDirCfg, charsmax(szDirCfg), "/next21_checkpoints")
	
	iDir = open_dir(szDirCfg, szFile, charsmax(szFile))
	
	if (!iDir)
	{
		server_print("[%s] Checkpoints were not loaded", PLUGIN)
		return
	}
	
	while (next_file(iDir, szFile, charsmax(szFile)))
	{
		if (szFile[0] == '.')
			continue
			
		if (equali(szMap, szFile))
		{
			format(szFile, charsmax(szFile), "%s/%s", szDirCfg, szFile)
			load_spawns(szFile)
			break
		}
	}
	
	close_dir(iDir)
}

load_spawns(const szFile[])
{	
	new iFile = fopen(szFile, "rt")
	
	if (!iFile)
	{
		server_print("[%s] Unable to open %s.", PLUGIN, szFile)
		return
	}
	
	new szLineData[512], szOrigin[3][24], Float: vOrigin[3], szAngle[24], Float: fAngle
	
	while (iFile && !feof(iFile))
	{
		fgets(iFile, szLineData, charsmax(szLineData))
			
		if (!szLineData[0] || szLineData[0] == ';')
			continue
						
		parse(szLineData, szOrigin[0], 23, szOrigin[1], 23, szOrigin[2], 23, szAngle, 23)
		
		vOrigin[0] = str_to_float(szOrigin[0])
		vOrigin[1] = str_to_float(szOrigin[1])
		vOrigin[2] = str_to_float(szOrigin[2])
		fAngle = str_to_float(szAngle)
				
		create_checkpoint(vOrigin, fAngle)
	}
	
	fclose(iFile)
	
	switch (g_iCheckpointsNum)
	{
		case 0: server_print("[%s] Checkpoints were not loaded", PLUGIN)
		case 1: server_print("[%s] Loaded one checkpoint", PLUGIN)
		default: server_print("[%s] Loaded %d checkpoints", PLUGIN, g_iCheckpointsNum)
	}

	apply_finish_bodypart()
}

create_checkpoint(const Float: vOrigin[3], const Float: fAngle)
{
	static bool: bEventsRegistration
		
	if (g_iCheckpointsNum == MAX_CHECKPOINTS)
		return NULLENT
		
	new iEnt = rg_create_entity("info_target", true)
	if (is_nullent(iEnt))
		return NULLENT
				
	engfunc(EngFunc_SetOrigin, iEnt, vOrigin)
	engfunc(EngFunc_SetModel, iEnt, MODEL_CHECKPOINT)
	engfunc(EngFunc_SetSize, iEnt, Float: {-CHECKPOINT_RADIUS, -CHECKPOINT_RADIUS, -CHECKPOINT_RADIUS},
		Float: {CHECKPOINT_RADIUS, CHECKPOINT_RADIUS, CHECKPOINT_RADIUS})
			
	new Float: vAngles[3]
	vAngles[1] = fAngle
	set_entvar(iEnt, var_origin, vOrigin)
	set_entvar(iEnt, var_angles, vAngles)
			
	set_entvar(iEnt, var_solid, SOLID_TRIGGER)
	set_entvar(iEnt, var_movetype, MOVETYPE_NOCLIP)
	set_entvar(iEnt, var_classname, CLASSNAME_CHECKPOINT)
	
	set_entvar(iEnt, var_framerate, 1.0)
	set_entvar(iEnt, var_colormap, random(256))
	
	#if defined COLOR_EFFECT
	set_entvar(iEnt, var_nextthink, get_gametime() + CHECKPOINT_COLORMAP_DELAY)
	#endif
	
	new Float: fGlow = g_pCvars[CVAR_CHECKPOINT_GLOW]
	if (fGlow > 0.0)
	{
		new Float: vColors[3]
		vColors[0] = random(256) + 0.0
		vColors[1] = random(256) + 0.0
		vColors[2] = random(256) + 0.0
		
		set_entvar(iEnt, var_renderfx, kRenderFxGlowShell)
		set_entvar(iEnt, var_renderamt, fGlow)
		set_entvar(iEnt, var_rendercolor, vColors)
	}
		
	if (g_pCvars[CVAR_CHECKPOINT_LIGHT])
		set_entvar(iEnt, var_effects, EF_DIMLIGHT)

	SetTouch(iEnt, "touch_checkpoint")
	#if defined COLOR_EFFECT
	SetThink(iEnt, "think_checkpoint")
	#endif
			
	g_iCheckpoint[g_iCheckpointsNum++] = iEnt
	
	if (!bEventsRegistration)
	{
		register_event("HLTV", "Event_RoundStart", "a", "1=0", "2=0")
		register_event("SendAudio", "Event_RoundEnd", "a", "2&%!MRAD_rounddraw")
		register_event("SendAudio", "Event_RoundEnd", "a", "2&%!MRAD_terwin")
		register_event("SendAudio", "Event_RoundEnd", "a", "2&%!MRAD_ctwin")

		RegisterHookChain(RG_CBasePlayer_Spawn, "CBasePlayer_Spawn_Post", true)
		
		Event_RoundStart()
		bEventsRegistration = true
	}
	
	return iEnt
}

apply_finish_bodypart()
{
	if (!g_iCheckpointsNum)	
		return
	
	new iEnt
	for (new i; i < g_iCheckpointsNum - 1; i++)
	{
		iEnt = g_iCheckpoint[i]
		set_entvar(iEnt, var_body, CP_BODY_NORMAL)
		set_entvar(iEnt, var_skin, CP_SKIN_NORMAL)
	}
	
	iEnt = g_iCheckpoint[g_iCheckpointsNum - 1]
	set_entvar(iEnt, var_body, CP_BODY_FINISH)
	set_entvar(iEnt, var_skin, CP_SKIN_FINISH)
}

save_checkpoints()
{
	new szDirCfg[128], szFile[128]
	get_configsdir(szDirCfg, charsmax(szDirCfg))
	add(szDirCfg, charsmax(szDirCfg), "/next21_checkpoints")
	
	get_mapname(szFile, charsmax(szFile))
	format(szFile, charsmax(szFile), "%s/%s.ini", szDirCfg, szFile)
	
	if (!dir_exists(szDirCfg))
		mkdir(szDirCfg)
	
	delete_file(szFile)
	
	if (!g_iCheckpointsNum)
		return 0
		
	new szText[128], Float: vOrigin[3], Float: vAngles[3]
	for (new i; i < g_iCheckpointsNum; i++)
	{
		get_entvar(g_iCheckpoint[i], var_origin, vOrigin)
		get_entvar(g_iCheckpoint[i], var_angles, vAngles)
		formatex(szText, charsmax(szText), "^"%f^" ^"%f^" ^"%f^" ^"%f^"",
			vOrigin[0], vOrigin[1], vOrigin[2], vAngles[2])
		write_file(szFile, szText)
	}
	
	return 0
}

/*** Editor menu ***/

create_menu_editor()
{
	new iMenu = menu_create(PLUGIN, "handler_checkpoint_menu")

	new iCallbackSpawn = menu_makecallback("callback_menu_spawn")
	new iCallbackRemove = menu_makecallback("callback_menu_remove")
	new iCallbackSave = menu_makecallback("callback_menu_save")

	menu_additem(iMenu, fmt("%L", LANG_SERVER, "MENU_SPAWN"), .callback=iCallbackSpawn)
	menu_additem(iMenu, fmt("%L", LANG_SERVER, "MENU_REMOVE"), .callback=iCallbackRemove)
	menu_additem(iMenu, fmt("%L^n", LANG_SERVER, "MENU_REMOVE_ALL"), .callback=iCallbackRemove)
	menu_additem(iMenu, fmt("%L", LANG_SERVER, "MENU_SAVE"), .callback=iCallbackSave)
	menu_setprop(iMenu, MPROP_EXITNAME, fmt("%L", LANG_SERVER, "MENU_EXIT"))

	return iMenu
}

display_checkpoint_menu(const iPlayer)
{
	menu_setprop(g_iMenuEditor, MPROP_TITLE, fmt("\r%L \y[\w%i/%i\y]",
		LANG_SERVER, "MENU_HEADER", g_iCheckpointsNum, MAX_CHECKPOINTS))
	menu_display(iPlayer, g_iMenuEditor)
}

public handler_checkpoint_menu(iPlayer, iMenu, iItem)
{
	if (iItem == MENU_EXIT)
		return PLUGIN_HANDLED
		
	switch (iItem)
	{
		case MENU_ITEM_CP_SPAWN:
		{
			new Float: vOrigin[3], Float: vAngles[3]
			fm_get_aim_origin(iPlayer, vOrigin)
			vOrigin[2] += CHECKPOINT_RADIUS
			get_entvar(iPlayer, var_v_angle, vAngles)
			
			if (create_checkpoint(vOrigin, vAngles[1]) != NULLENT)
			{
				apply_finish_bodypart()
				g_bWasChanged = true
				
				if (check_stuck(vOrigin, iPlayer))
					client_print_color(iPlayer, print_team_red, "%s ^1%L", CHAT_PREFIX, iPlayer, "CP_CAN_STUCK")
			}
		}
		case MENU_ITEM_CP_REMOVE:
		{
			set_entvar(g_iCheckpoint[--g_iCheckpointsNum], var_flags, FL_KILLME)
			if (g_iCheckpointsNum > 0)
				apply_finish_bodypart()
				
			g_bWasChanged = true
		}
		case MENU_ITEM_CP_REMOVEALL:
		{
			for (new i; i < g_iCheckpointsNum; i++)
				set_entvar(g_iCheckpoint[i], var_flags, FL_KILLME)
				
			g_iCheckpointsNum = 0
			g_bWasChanged = true
		}
		case MENU_ITEM_CP_SAVE:
		{
			if (!save_checkpoints())
			{
				client_print_color(iPlayer, print_team_red, "%s ^1%L", CHAT_PREFIX, iPlayer, "CP_SAVED")
				g_bWasChanged = false
									
				arrayset(g_iPlrCompleted, -1, MAX_PLAYERS + 1)
				g_iFinishedNum = 0
			}
		}
	}
	
	display_checkpoint_menu(iPlayer)
	return PLUGIN_CONTINUE
}

public callback_menu_spawn()
{
	return g_iCheckpointsNum < MAX_CHECKPOINTS ? ITEM_IGNORE : ITEM_DISABLED
}

public callback_menu_remove()
{
	return g_iCheckpointsNum > 0 ? ITEM_IGNORE : ITEM_DISABLED
}

public callback_menu_save()
{
	return g_bWasChanged ? ITEM_IGNORE : ITEM_DISABLED
}

/*** Global events ***/

public Event_RoundStart()
{
	g_iRoundEnd = 0
	
	arrayset(g_iPlrCompleted, -1, MAX_PLAYERS + 1)
	g_iFinishedNum = 0
}

public Event_RoundEnd()
{	
	g_iRoundEnd = 1
}

/*** Player events ***/

public clcmd_checkpoint_menu(id, level, cid)
{
	if (cmd_access(id, level, cid, 1))
		display_checkpoint_menu(id)
	
	return PLUGIN_HANDLED
}

public client_putinserver(id)
{
	g_iPlrCompleted[id] = -1
}

public CBasePlayer_Spawn_Post(const iPlayer)
{
	remove_task(iPlayer + TASK_RETURN_PLAYER)
	if (g_pCvars[CVAR_CHECKPOINT_TELEPORT] && g_iPlrCompleted[iPlayer] > -1)
	{
		if (!return_player(iPlayer, g_iPlrCompleted[iPlayer]))
			set_task(0.5, "task_teleport_player", iPlayer + TASK_RETURN_PLAYER,
				.flags = "a", .repeat = RETURN_PLAYER_TRY_TIMES)
	}
}

public task_return_player(iTaskId)
{
	new iPlayer = iTaskId - TASK_RETURN_PLAYER
	
	if (g_iPlrCompleted[iPlayer] >= g_iCheckpointsNum)
		g_iPlrCompleted[iPlayer] = -1
	
	if (!is_user_alive(iPlayer))
	{
		remove_task(iTaskId)
		return
	}
		
	if (return_player(iPlayer, g_iPlrCompleted[iPlayer]))
	{
		print_skip_ad(iPlayer)
		remove_task(iTaskId)
	}
}

public task_teleport_player(iTaskId)
{
	new iPlayer = iTaskId - TASK_RETURN_PLAYER
	
	if (!is_user_alive(iPlayer))
	{
		remove_task(iTaskId)
		return
	}
	
	if (g_iPlrCompleted[iPlayer] >= g_iCheckpointsNum
		|| return_player(iPlayer, g_iPlrCompleted[iPlayer]))
	{
		remove_task(iTaskId)
	}
}

/*** Checkpoint's actions ***/

public touch_checkpoint(const iEnt, const iPlayer)
{
	if (g_iRoundEnd || g_bWasChanged)
		return HC_CONTINUE

	#if defined DUELS_ENABLED		
	if (g_bDuelStarted)
		return HC_CONTINUE
	#endif

	if (!is_user_alive(iPlayer))
		return HC_CONTINUE
	
	new iPos
	for (new i; i < g_iCheckpointsNum; i++)
	{
		if (g_iCheckpoint[i] == iEnt)
		{
			iPos = i
			break
		}
	}
		
	if (g_iPlrCompleted[iPlayer] >= iPos)
		return HC_CONTINUE
		
	new iSkipLimit = g_pCvars[CVAR_CHECKPOINT_SKIP_LIMIT]
	if (iSkipLimit && iPos - g_iPlrCompleted[iPlayer] > iSkipLimit)
	{
		if (return_player(iPlayer, g_iPlrCompleted[iPlayer]))
			print_skip_ad(iPlayer)
		else if (!task_exists(iPlayer + TASK_RETURN_PLAYER))
			set_task(0.5, "task_return_player", iPlayer + TASK_RETURN_PLAYER,
				.flags = "a", .repeat = RETURN_PLAYER_TRY_TIMES)
	
		return HC_CONTINUE
	}
	
	client_cmd(iPlayer, "spk %s", SOUND_CHECKPOINT)
	
	new iReward
	set_dhudmessage(DHUD_POSITION)

	if (iPos == g_iCheckpointsNum - 1)
	{
		show_dhudmessage(iPlayer, "%L", iPlayer, "CP_FINISH", ++g_iFinishedNum)
		
		new szPlayerName[24]
		get_shorted_player_name(iPlayer, szPlayerName, charsmax(szPlayerName))		
		client_print_color(0, print_team_red, "%s ^1%L", CHAT_PREFIX, LANG_PLAYER, "FINISH_AD", szPlayerName, g_iFinishedNum)
				
		if (g_iFinishedNum > 3)
		{
			iReward = g_pCvars[CVAR_CHECKPOINT_REWARD]
			if (g_pCvars[CVAR_CHECKPOINT_MUL])
				iReward *= iPos + 1
		}
		else
			iReward = g_pCvars[CVAR_CHECKPOINT_FINISH_REWARD][g_iFinishedNum - 1]
	}
	else
	{
		show_dhudmessage(iPlayer, "%L", iPlayer, "CP_COMPLETE", iPos + 1)
		
		iReward = g_pCvars[CVAR_CHECKPOINT_REWARD]
		if (g_pCvars[CVAR_CHECKPOINT_MUL])
			iReward *= iPos + 1
	}
	
	if (iReward)
	{
		rg_add_account(iPlayer, iReward)
		client_print_color(iPlayer, print_team_red, "%s ^1%L", CHAT_PREFIX, iPlayer, "CP_REWARD", iReward)
	}
	
	g_iPlrCompleted[iPlayer] = iPos
	
	return HC_CONTINUE
}

public think_checkpoint(const iEnt)
{
	new iTopColor = (get_entvar(iEnt, var_colormap) + 1) % 256
	set_entvar(iEnt, var_colormap, iTopColor)
	set_entvar(iEnt, var_nextthink, get_gametime() + CHECKPOINT_COLORMAP_DELAY)
		
	return HC_CONTINUE
}

/*** Cvars ***/

register_cvars()
{
	bind_pcvar_num(register_cvar("n21_checkpoint_reward", "300"), g_pCvars[CVAR_CHECKPOINT_REWARD])
	bind_pcvar_num(register_cvar("n21_checkpoint_money_mul", "1"), g_pCvars[CVAR_CHECKPOINT_MUL])
	bind_pcvar_num(register_cvar("n21_checkpoint_money_last_first", "6000"), g_pCvars[CVAR_CHECKPOINT_FINISH_REWARD][0])
	bind_pcvar_num(register_cvar("n21_checkpoint_money_last_second", "4000"), g_pCvars[CVAR_CHECKPOINT_FINISH_REWARD][1])
	bind_pcvar_num(register_cvar("n21_checkpoint_money_last_third", "3500"), g_pCvars[CVAR_CHECKPOINT_FINISH_REWARD][2])
	bind_pcvar_num(register_cvar("n21_checkpoint_teleport", "0"), g_pCvars[CVAR_CHECKPOINT_TELEPORT])	
	bind_pcvar_num(register_cvar("n21_checkpoint_skip_limit", "0"), g_pCvars[CVAR_CHECKPOINT_SKIP_LIMIT])

	new pCvarLight = register_cvar("n21_checkpoint_light_effect", "0")
	new pCvarGlowEffect = register_cvar("n21_checkpoint_glow_effect", "0.0", true, 0.0)

	bind_pcvar_num(pCvarLight, g_pCvars[CVAR_CHECKPOINT_LIGHT])
	bind_pcvar_float(pCvarGlowEffect, g_pCvars[CVAR_CHECKPOINT_GLOW])
	hook_cvar_change(pCvarLight, "cvar_light_changed")
	hook_cvar_change(pCvarGlowEffect, "cvar_glow_effect_changed")
}

public cvar_light_changed(pCvar, const szOldValue[], const szNewValue[])
{
	new bool: isLightEnabled = str_to_num(szNewValue) > 0
	for (new i, iEnt, iEffects; i < g_iCheckpointsNum; i++)
	{
		iEnt = g_iCheckpoint[i]
		iEffects = get_entvar(iEnt, var_effects)
		set_entvar(iEnt, var_effects,
			isLightEnabled ? (iEffects | EF_DIMLIGHT) : (iEffects & ~EF_DIMLIGHT))
	}
}

public cvar_glow_effect_changed(pCvar, const szOldValue[], const szNewValue[])
{
	new Float: fGlow = str_to_float(szNewValue)
	for (new i, iEnt; i < g_iCheckpointsNum; i++)
	{
		iEnt = g_iCheckpoint[i]
		if (fGlow > 0.0)
		{
			new Float: vColors[3]
			vColors[0] = random(256) + 0.0
			vColors[1] = random(256) + 0.0
			vColors[2] = random(256) + 0.0

			set_entvar(iEnt, var_renderfx, kRenderFxGlowShell)
			set_entvar(iEnt, var_renderamt, fGlow)
			set_entvar(iEnt, var_rendercolor, vColors)
		}
		else
			set_entvar(iEnt, var_renderfx, kRenderFxNone)
	}
}

/*** Other stuff ***/

bool: return_player(const iPlayer, const iPos)
{
	new Float: vOrigin[3], Float: vAngles[3]
	
	if (iPos == -1)
	{
		new iSpawnEnts[32], iSpawnNum, iSpawn = -1
		
		while ((iSpawn = rg_find_ent_by_class(iSpawn, "info_player_start", true)))
			iSpawnEnts[iSpawnNum++] = iSpawn

		get_entvar(iSpawnEnts[random(iSpawnNum)], var_origin, vOrigin)
	}
	else
	{
		get_entvar(g_iCheckpoint[iPos], var_origin, vOrigin)
		get_entvar(g_iCheckpoint[iPos], var_angles, vAngles)
	}
	
	if (check_stuck(vOrigin, iPlayer))
		return false

	engfunc(EngFunc_SetOrigin, iPlayer, vOrigin)
	set_entvar(iPlayer, var_origin, vOrigin)
	set_entvar(iPlayer, var_angles, vAngles)
	set_entvar(iPlayer, var_v_angle, vAngles)
	set_entvar(iPlayer, var_fixangle, 1)
	set_entvar(iPlayer, var_velocity, NULL_VECTOR)
	
	return true
}

print_skip_ad(const iPlayer)
{
	new szPlayerName[18]
	get_shorted_player_name(iPlayer, szPlayerName, charsmax(szPlayerName))
	client_print_color(0, print_team_red, "%s ^1%L", CHAT_PREFIX, iPlayer, "CP_RETURN", szPlayerName)
}

bool: check_stuck(const Float: vOrigin[3], const iPlayer)
{
	static tr
	engfunc(EngFunc_TraceHull, vOrigin, vOrigin, 0, HULL_HUMAN, iPlayer, tr)
	return get_tr2(tr, TR_StartSolid) && get_tr2(tr, TR_AllSolid)
}

get_shorted_player_name(const iPlayer, szPlayerName[], const iLen)
{
	get_user_name(iPlayer, szPlayerName, iLen)
	if (szPlayerName[iLen - 1] != 0)
		szPlayerName[iLen - 1] = szPlayerName[iLen - 2] = szPlayerName[iLen - 3] = '.'
}

/*** Duel forwards ***/

#if defined DUELS_ENABLED
public dr_duel_start(iPlayerCT, iPlayerTE)
{
	g_bDuelStarted = true
	remove_task(iPlayerCT + TASK_RETURN_PLAYER)
	remove_task(iPlayerTE + TASK_RETURN_PLAYER)
}
public dr_duel_finish() g_bDuelStarted = false
public dr_duel_canceled() g_bDuelStarted = false
#endif
