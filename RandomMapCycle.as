// RandomMapCycle.as
// Rotacion aleatoria sin repetir hasta agotar los mapas.
// El estado se conserva entre mapas, hasta reiniciar o recargar el plugin.

array<string> g_Source;
array<string> g_Remaining;
uint g_MapGeneration = 0;
bool g_SelectionScheduled = false;
string g_SelectedMap;


void PluginInit()
{
    g_Module.ScriptInfo.SetAuthor("gdani4l");
    g_Module.ScriptInfo.SetContactInfo("adsdas");
}

void MapInit()
{
    ++g_MapGeneration;
    g_SelectionScheduled = false;
    g_SelectedMap = "";
}

void MapActivate()
{
    if (g_SelectionScheduled)
        return;

    g_SelectionScheduled = true;
    g_Scheduler.SetTimeout("PrepareRandomNextMap", 3.0f, g_MapGeneration);
}

// Only permit plain map names when building a server console command.
bool SafeMapName(const string& in name)
{
    if (name.Length() == 0)
        return false;
    for (uint i = 0; i < name.Length(); ++i)
    {
        uint8 c = name[i];
        if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) ||
            (c >= 97 && c <= 122) || c == 95 || c == 45)
            continue;
        return false;
    }
    return true;
}

bool SourceChanged(const array<string>& in maps)
{
    if (maps.length() != g_Source.length())
        return true;

    for (uint i = 0; i < maps.length(); ++i)
    {
        if (maps[i] != g_Source[i])
            return true;
    }

    return false;
}

void ShuffleRemaining()
{
    // Fisher-Yates.
    for (int i = int(g_Remaining.length()) - 1; i > 0; --i)
    {
        int j = Math.RandomLong(0, i);
        string temp = g_Remaining[i];
        g_Remaining[i] = g_Remaining[j];
        g_Remaining[j] = temp;
    }
}

void RemovePlayedMap(const string& in currentMap)
{
    int index = g_Remaining.find(currentMap);

    if (index >= 0)
        g_Remaining.removeAt(uint(index));
}

void PrepareRandomNextMap(uint generation)
{
    // Discard callbacks belonging to a previous map load.
    if (generation != g_MapGeneration || g_SelectedMap != "")
        return;
    g_EngineFuncs.ServerPrint(
    "[RandomMapCycle] Ejecutando seleccion aleatoria...\n"
);
    array<string>@ cycle = g_MapCycle.GetMapCycle();

    if (cycle is null || cycle.length() == 0)
    {
        g_Game.AlertMessage(
            at_console,
            "[RandomMapCycle] El mapcycle esta vacio.\n"
        );
        return;
    }

    // Validar mapas y eliminar duplicados.
    array<string> validMaps;

    for (uint i = 0; i < cycle.length(); ++i)
    {
        string mapName = cycle[i];

        if (!SafeMapName(mapName) || !g_EngineFuncs.IsMapValid(mapName))
            continue;

        if (validMaps.find(mapName) < 0)
            validMaps.insertLast(mapName);
    }

    if (validMaps.length() == 0)
    {
        g_Game.AlertMessage(
            at_console,
            "[RandomMapCycle] No hay mapas validos en el mapcycle.\n"
        );
        return;
    }

    string currentMap = string(g_Engine.mapname);

    // Si cambia el mapcycle, reconstruir la rotacion.
    if (SourceChanged(validMaps))
    {
        g_Source = validMaps;
        g_Remaining = validMaps;
        ShuffleRemaining();
    }

    // Solo consumir mapas que realmente se hayan iniciado.
    RemovePlayedMap(currentMap);

    if (g_Remaining.length() == 0)
    {
        g_Remaining = g_Source;
        ShuffleRemaining();

        // Evitar repetir inmediatamente el mapa actual.
        // Conservarlo en la lista para jugarlo despues.
        if (g_Remaining.length() > 1 &&
            g_Remaining[0] == currentMap)
        {
            int j = Math.RandomLong(
                1, int(g_Remaining.length()) - 1
            );

            string temp = g_Remaining[0];
            g_Remaining[0] = g_Remaining[j];
            g_Remaining[j] = temp;
        }
    }

    g_SelectedMap = g_Remaining[0];

    // Let the engine process the command normally; do not flush the
    // entire server command buffer from inside an AngelScript callback.
    g_EngineFuncs.ServerCommand(
        "mp_nextmap_cycle \"" + g_SelectedMap + "\"\n"
    );
    g_EngineFuncs.ServerPrint(
        "[RandomMapCycle] Solicitado: " + g_SelectedMap + "\n"
    );
    g_Scheduler.SetTimeout("VerifyRandomNextMap", 1.0f, generation);
}

void VerifyRandomNextMap(uint generation)
{
    if (generation != g_MapGeneration)
        return;

    string actual = g_EngineFuncs.CVarGetString("mp_nextmap_cycle");
    if (actual == g_SelectedMap)
    {
        g_EngineFuncs.ServerPrint(
            "[RandomMapCycle] OK. Siguiente mapa: " + actual + "\n"
        );
    }
    else
    {
        g_EngineFuncs.ServerPrint(
            "[RandomMapCycle] ERROR: solicitado=" + g_SelectedMap +
            " | mp_nextmap_cycle=" + actual +
            ". Revisar consola y configuracion del servidor.\n"
        );
    }
}
