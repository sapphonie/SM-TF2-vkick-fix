#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <sourcebanspp>

Handle RenderSteamID;
ConVar sm_votekick_ban_reason;
ConVar sm_votekick_ban_length;

public void OnPluginStart()
{
    // Our base gamedata file
    GameData vkick_gamedata = LoadGameConfigFile("vkick_fix");
    if (!vkick_gamedata)
    {
        SetFailState("Failed to load vkick_fix gamedata.");
        return;
    }

    {
        Handle CKickIssue_ExecuteCommand = DHookCreateFromConf(vkick_gamedata, "CKickIssue::ExecuteCommand");
        if (!CKickIssue_ExecuteCommand)
        {
            SetFailState("Failed to setup detour for CKickIssue::ExecuteCommand");
        }
        // detour
        if ( !DHookEnableDetour(CKickIssue_ExecuteCommand, false /* detour */, Detour_CKickIssue__ExecuteCommand) )
        {
            SetFailState("Failed to detour CKickIssue::ExecuteCommand.");
        }
        PrintToServer("CKickIssue::ExecuteCommand detoured!");
    }


    {
        StartPrepSDKCall( SDKCall_Raw );
        PrepSDKCall_SetFromConf( vkick_gamedata, SDKConf_Signature, "RenderSteamID" );
        PrepSDKCall_SetReturnInfo(SDKType_String, SDKPass_Plain);
        RenderSteamID = EndPrepSDKCall();
        if ( RenderSteamID != INVALID_HANDLE )
        {
            PrintToServer( "RenderSteamID set up!" );
        }
        else
        {
            SetFailState( "Failed to get RenderSteamID siggy." );
        }
    }

    sm_votekick_ban_length = CreateConVar("sm_votekick_ban_length", "10",                       "Ban length for votekick detour", FCVAR_NONE, true, 0.0, false);
    sm_votekick_ban_reason = CreateConVar("sm_votekick_ban_reason", "Votekicked from server",   "Ban reason for votekick detour", FCVAR_NONE);

}


public MRESReturn Detour_CKickIssue__ExecuteCommand(Address pThis)
{
    LogMessage("-> [CKickIssue__ExecuteCommand] SOMEONE got kicked. Let's try to detour that...");

    // sub_10526100();
    // v2 = ecx0 + 46;
    // v3 = sub_103082C0(ecx0 + 46);
    // sub_103082C0 == steamid.Render(), ret's a char ptr
    // 46 == 0x2E
    char steamid[128];
    SDKCall( RenderSteamID, pThis + view_as<Address>(0x2E * 4), steamid, sizeof(steamid) );

    LogMessage("-> [CKickIssue__ExecuteCommand] Rendered SteamID = %s", steamid);

    // Invalid steamid (bot, and other nonsense)
    if ( StrContains(steamid, "[U:") == -1 )
    {
        // Try anyway. This might explode.
        // Format(command, sizeof(command), "kickid \"%s\" %s\n", steamid, "hi" );
        // ServerCommand(command);
        // return MRES_Supercede;

        // Just kidding we're going to let the engine handle it for now...
        LogMessage("-> [CKickIssue__ExecuteCommand] Bad SteamID %s, not interfering...", steamid);
        return MRES_Ignored;
    }

    static int banLength = 10;
    banLength = sm_votekick_ban_length.IntValue;

    char banReason[256] = {};
    sm_votekick_ban_reason.GetString(banReason, sizeof(banReason));

    // sourcebans check
    if (GetFeatureStatus(FeatureType_Native, "SBPP_BanPlayer") != FeatureStatus_Available)
    {
        char command[1024] = {};

        Format(command, sizeof(command), "sm_ban #%s %i %s\n", steamid, banLength, banReason);
        ServerCommand(command);

        LogMessage("-> [CKickIssue__ExecuteCommand] Did ban with cmd = \n%s", command);
    }
    else
    {
        int client = FindClientBySteamId(steamid, AuthId_Steam3);

        if ( client <= 0 || !IsClientConnected(client) || !IsClientInGame(client) || !IsClientAuthorized(client) || !IsClientInGame(client) )
        {
            LogError("Client %i (%L) is invalid! Can't use SourceBans to ban them...", client, client);
            // BAIL!!!!!
            return MRES_Ignored;
        }

        SBPP_BanPlayer(0 /* console */, client, banLength, banReason);
        LogMessage
        (
            "-> [CKickIssue__ExecuteCommand] Did ban with SBPP_BanPlayer %i %i (%L) %i %s\n",
            0, client, client, banLength, banReason
        );
    }

    return MRES_Supercede;
}

// Digby :D !!!!!!!
int FindClientBySteamId(const char[] auth, AuthIdType type)
{
    char tempAuth[MAX_AUTHID_LENGTH];
    
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
        {
            continue;
        }
        if (!GetClientAuthId(i, type, tempAuth, sizeof(tempAuth)))
        {
            continue;
        }
        if (StrEqual(auth, tempAuth, false))
        {
            return i;
        }
    }

    return -1;
}
