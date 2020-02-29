// © Maxim "Kailo" Telezhenko, 2015
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>

#include <cstrike>
#include <sdktools>

#pragma newdecls required
#pragma semicolon 1

#define T_COLOR		"245 255 193"
#define CT_COLOR	"195 236 255"
#define RED_COLOR	"255 0 0"

ArrayList g_scenes;
Menu g_menus[MAXPLAYERS + 1];
int g_lastscene[MAXPLAYERS + 1] = {-1, ...};

public void OnPluginStart()
{
	RegAdminCmd("sm_dead", Command_Dead, ADMFLAG_GENERIC);

	HookEvent("player_hurt", OnPlayerHurt);
	HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);

	g_scenes = new ArrayList();
}

public void OnPluginEnd()
{
	DeleteAllScenes();
	delete g_scenes;
}

public Action Command_Dead(int client, int args)
{
	if (client)
		if (g_scenes.Length)
			ShowDeadMenu(client);
		else
			ReplyToCommand(client, "[SM] Нет убитых игроков в этом раунде.");

	return Plugin_Handled;
}

public void OnPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!event.GetInt("health")) {
		int attacker = GetClientOfUserId(event.GetInt("attacker"));
		char weapon[64];
		event.GetString("weapon", weapon, sizeof(weapon));

		if (attacker && StrContains(weapon, "knife") == -1)
			AddScene(GetClientOfUserId(event.GetInt("userid")), attacker);
	}
}

void ShowDeadMenu(int client, int item = 0)
{
	Menu menu = new Menu(DeadMenu);
	menu.AddItem("", "Телепортироваться");
	StringMap map;
	char victim_name[MAX_NAME_LENGTH], attacker_name[MAX_NAME_LENGTH], display[64];
	int size = g_scenes.Length;
	for (int i = 0; i < size; i++) {
		map = g_scenes.Get(i);
		map.GetString("victim_name", victim_name, sizeof(victim_name));
		map.GetString("attacker_name", attacker_name, sizeof(attacker_name));
		FormatEx(display, sizeof(display), "%s убит игроком %s", victim_name, attacker_name);
		menu.AddItem("", display);
	}
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);
	g_menus[client] = menu;
}

public int DeadMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action) {
		case MenuAction_Select: {
			if (param2) {
				int scene = param2 - 1;
				StringMap map = g_scenes.Get(scene);
				bool show;
				map.GetValue("show", show);
				if (!show) {
					g_lastscene[param1] = scene;
					if (ShowScene(scene))
						PrintToChat(param1, "[SM] Сцена #%d показана.", scene);
					else
						PrintToChat(param1, "[SM] Неудалось показать сцену #%d.", scene);
				}
				else {
					HideScene(scene);
					PrintToChat(param1, "[SM] Сцена #%d скрыта.", scene);
				}
			}
			else
				if (g_lastscene[param1] != -1) {
					StringMap map = g_scenes.Get(g_lastscene[param1]);
					float pos[3], ang[3];
					map.GetArray("attacker_pos", pos, sizeof(pos));
					map.GetArray("attacker_ang", ang, sizeof(ang));
					TeleportEntity(param1, pos, ang, NULL_VECTOR);
				}
				else
					PrintToChat(param1, "[SM] Сначала выбирите сцену.");
			ShowDeadMenu(param1, menu.Selection);
		}
		case MenuAction_Cancel: g_menus[param1] = null;
		case MenuAction_End: delete menu;
	}
}

void AddScene(int victim, int attacker)
{
	StringMap map = new StringMap();
	map.SetValue("show", false);
	SetPlayerSenceInfo(map, victim, "victim");
	SetPlayerSenceInfo(map, attacker, "attacker");
	float pos[3], ang[3], origin[3];
	GetClientEyePosition(attacker, pos);
	GetClientEyeAngles(attacker, ang);
	Handle trace = TR_TraceRayFilterEx(pos, ang, MASK_SHOT, RayType_Infinite, TraceFilter, victim);
	if (TR_DidHit(trace))
			TR_GetEndPosition(origin, trace);
	CloseHandle(trace);
	map.SetArray("hit_origin", origin, sizeof(origin));
	g_scenes.Push(map);
}

void SetPlayerSenceInfo(StringMap map, int client, const char[] tag)
{
	map.SetValue(tag, client);
	char key[32], name[MAX_NAME_LENGTH];
	FormatEx(key, sizeof(key), "%s_name", tag);
	GetClientName(client, name, sizeof(name));
	map.SetString(key, name);
	float vec[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vec);
	FormatEx(key, sizeof(key), "%s_pos", tag);
	map.SetArray(key, vec, sizeof(vec));
	GetEntPropVector(client, Prop_Send, "m_angRotation", vec);
	vec[0] = 0.0;
	FormatEx(key, sizeof(key), "%s_ang", tag);
	map.SetArray(key, vec, sizeof(vec));
	char model[PLATFORM_MAX_PATH];
	GetClientModel(client, model, sizeof(model));
	FormatEx(key, sizeof(key), "%s_model", tag);
	map.SetString(key, model);
	FormatEx(key, sizeof(key), "%s_duck", tag);
	map.SetValue(key, GetEntProp(client, Prop_Send, "m_bDucked"));
	FormatEx(key, sizeof(key), "%s_color", tag);
	map.SetString(key, GetClientTeam(client) == CS_TEAM_T ? T_COLOR : CT_COLOR);
}

public bool TraceFilter(int entity, int contentsMask, any victim)
{
	return entity == victim;
}

bool ShowScene(int index)
{
	StringMap map = g_scenes.Get(index);
	int victim_ent = CreatePlayerGhost(map, "victim");
	if (victim_ent != -1) {
		int attacker_ent = CreatePlayerGhost(map, "attacker");
		if (attacker_ent != -1) {
			map.SetValue("show", true);
			map.SetValue("victim_ent", EntIndexToEntRef(victim_ent));
			map.SetValue("attacker_ent", EntIndexToEntRef(attacker_ent));
			float pos[3], origin[3];
			map.GetArray("attacker_pos", pos, sizeof(pos));
			bool duck;
			map.GetValue("attacker_duck", duck);
			pos[2] += duck ? 46.0 : 64.0;
			map.GetArray("hit_origin", origin, sizeof(origin));
			char color[12];
			map.GetString("attacker_color", color, sizeof(color));
			int beam = CreateBeam(pos, origin, color);
			if (beam != -1)
				map.SetValue("beam", EntIndexToEntRef(beam));

			return true;
		}
		AcceptEntityInput(victim_ent, "Kill");
	}

	return false;
}

int CreateBeam(const float pos[3], const float origin[3], const char[] color)
{
	int entity = CreateEntityByName("env_beam");
	if (entity != -1) {
		DispatchKeyValue(entity, "renderamt", "255");
		DispatchKeyValue(entity, "rendercolor", color);
		DispatchKeyValue(entity, "life", "0");
		DispatchKeyValue(entity, "texture", "sprites/laserbeam.spr");
		char name[64];
		FormatEx(name, sizeof(name), "beam%d", entity);
		DispatchKeyValue(entity, "targetname", name);
		DispatchKeyValue(entity, "LightningStart", name);
		DispatchKeyValueVector(entity, "targetpoint", origin);
		DispatchKeyValue(entity, "spawnflags", "1");
		TeleportEntity(entity, pos, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(entity);
		ActivateEntity(entity);
	}

	return entity;
}

void HideScene(int index)
{
	StringMap map = g_scenes.Get(index);
	map.SetValue("show", false);
	RemovePlayerGhost(map, "victim_ent");
	RemovePlayerGhost(map, "attacker_ent");
	int beam;
	map.GetValue("beam", beam);
	beam = EntRefToEntIndex(beam);
	if (IsValidEntity(beam))
		AcceptEntityInput(beam, "Kill");
	map.Remove("beam");
}

void RemovePlayerGhost(StringMap map, const char[] key)
{
	int ghost_ent;
	map.GetValue(key, ghost_ent);
	ghost_ent = EntRefToEntIndex(ghost_ent);
	if (IsValidEntity(ghost_ent))
		AcceptEntityInput(ghost_ent, "Kill");
	map.Remove(key);
}

void DeleteAllScenes()
{
	int size = g_scenes.Length;
	if (size) {
		for (int i = 1; i <= MaxClients; i++) {
			if (g_menus[i])
				g_menus[i].Cancel();
			g_lastscene[i] = -1;
		}
		StringMap map;
		bool show;
		for (int i = 0; i < size; i++) {
			map = g_scenes.Get(i);
			map.GetValue("show", show);
			if (show)
				HideScene(i);
			delete map;
		}
		g_scenes.Clear();
	}
}

public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	DeleteAllScenes();
}

int CreatePlayerGhost(StringMap map, const char[] tag)
{
	char key[32], model[PLATFORM_MAX_PATH], color[12];
	FormatEx(key, sizeof(key), "%s_model", tag);
	map.GetString(key, model, sizeof(model));
	FormatEx(key, sizeof(key), "%s_duck", tag);
	bool duck;
	map.GetValue(key, duck);
	FormatEx(key, sizeof(key), "%s_ang", tag);
	float ang[3], pos[3];
	map.GetArray(key, ang, sizeof(ang));
	FormatEx(key, sizeof(key), "%s_pos", tag);
	map.GetArray(key, pos, sizeof(pos));
	if (!StrEqual(tag, "attacker")) {
		FormatEx(key, sizeof(key), "%s_color", tag);
		map.GetString(key, color, sizeof(color));
	} else
		color = RED_COLOR;

	return CreatePlayerGhostModel(model, duck, ang, pos, color);
}

int CreatePlayerGhostModel(const char[] model, bool ducked, const float ang[3], const float pos[3], const char[] color)
{
	int entity = CreateEntityByName("prop_dynamic_glow");
	if (entity != -1) {
		DispatchKeyValue(entity, "model", model);
		DispatchKeyValue(entity, "renderamt", "112");
		DispatchKeyValue(entity, "rendermode", "4");
		DispatchKeyValue(entity, "HoldAnimation", "1");
		if (ducked)
			DispatchKeyValue(entity, "DefaultAnim", "heavy_deploy_crouch");
		else
			DispatchKeyValue(entity, "DefaultAnim", "default");
		// char angString[512];
		// Format(angString, sizeof(angString), "%f %f %f", ang[0], ang[1], ang[2]);
		// DispatchKeyValue(entity, "angles", angString);
		DispatchKeyValue(entity, "glowcolor", color);
		DispatchKeyValue(entity, "glowenabled", "1");
		DispatchSpawn(entity);
		TeleportEntity(entity, pos, ang, NULL_VECTOR);
	}

	return entity;
}