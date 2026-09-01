// ============================================================================
// Ammo Shop - Sven Co-op AngelScript plugin
//
// "Buy menu" que permite a cualquier jugador comprar municion de cada arma.
// Se abre con  .ammo  en el chat.
//
// - DINERO: moneda propia, separada del score. Ganas dinero igual a los frags
//   que haces (si tu score sube en N, ganas N de dinero). Comprar descuenta
//   del DINERO, nunca de tus frags.
// - El dinero se muestra siempre en la parte central-baja de la pantalla, con
//   los numeros por sprite del juego (igual que el velocimetro .vel).
// - Puedes comprar aunque tengas la municion al maximo: en ese caso la
//   municion se dropea al piso.
// ============================================================================

// --- Configuracion -----------------------------------------------------------
const string OPEN_COMMAND = "buy"; // comando de chat para abrir la tienda

const uint8 HUD_CHANNEL         = 6;      // canal del display numerico (0-15).
                                          // Distinto al del velocimetro (5) para no pisarlo.
const float HUD_POS_X           = 0.0f;   // 0 = centrado (por HUD_ELEM_SCR_CENTER_X)
const float HUD_POS_Y           = 0.965f;  // parte baja de la pantalla
const float HUD_UPDATE_INTERVAL = 0.2f;   // segundos entre refrescos del HUD

const string SOUND_AMMO_PICKUP  = "items/9mmclip1.wav"; // Sonido de recoleccion

// --- Catalogo ----------------------------------------------------------------
class AmmoItem {
  string ammoName;
  string entityName;
  string label;
  int amount;
  int cost;
  AmmoItem() {}
  AmmoItem(const string& in n, const string& in e, const string& in l, int a, int c) {
    ammoName = n; entityName = e; label = l; amount = a; cost = c;
  }
}

array<AmmoItem> g_ammo = {
  //        ammoName          entidad a dropear     etiqueta en el menu              cant.  precio
  AmmoItem("9mm",            "ammo_9mmAR",        "9mmAR",                         50,    10),
  AmmoItem("357",            "ammo_357",          ".357",                          6,     0),
  AmmoItem("buckshot",       "ammo_buckshot",     "Buckshot",                      8,    0),
  AmmoItem("bolts",          "ammo_crossbow",     "Crossbow",                      5,     0),
  AmmoItem("argrenades",     "ammo_ARgrenades",   "AR grenades",                   2,     0),
  AmmoItem("rockets",        "ammo_rpgclip",      "Rpg clip",                      1,     0),
  AmmoItem("uranium",        "ammo_gaussclip",    "Gauss clip",                    20,    0),
  AmmoItem("556",            "ammo_556",          "5.56 (M249 SAW)",               100,    0),
  AmmoItem("m40a1",          "ammo_762",          "7.62 (Sniper Rifle)",           5,     0),
  AmmoItem("sporeclip",      "ammo_sporeclip",    "Spores (Spore Launcher)",       1,     0),
  AmmoItem("hand grenade",   "weapon_handgrenade","Hand grenade",                  5,     0),
  AmmoItem("satchel charge", "weapon_satchel",    "Satchel",                       1,     0),
  AmmoItem("trip mine",      "weapon_tripmine",   "Trip mine",                     1,     0),
  AmmoItem("snarks",         "weapon_snark",      "Snarks",                        5,     0)
};

// --- Estado ------------------------------------------------------------------
dictionary   g_money;               // SteamID -> dinero (double)
array<float> g_lastFrags(33, 0.0f); // score anterior por jugador (para el delta)
array<float> g_nextHud(33, 0.0f);   // proximo refresco de HUD por jugador
array<CTextMenu@> g_menus(33);      // menus abiertos (mantener el handle vivo)

// -----------------------------------------------------------------------------
void PluginInit() {
  g_Module.ScriptInfo.SetAuthor("STEAM_0:1:208354404");
  g_Module.ScriptInfo.SetContactInfo("N/A");

  g_Hooks.RegisterHook(Hooks::Player::ClientSay,         @ClientSay);
  g_Hooks.RegisterHook(Hooks::Player::PlayerPostThink,   @PlayerPostThink);
  g_Hooks.RegisterHook(Hooks::Player::ClientPutInServer, @ClientPutInServer);
}

// -----------------------------------------------------------------------------
void MapInit() {
  // Precache obligatorio para que el motor cargue el sonido
  g_SoundSystem.PrecacheSound(SOUND_AMMO_PICKUP);
}

// -----------------------------------------------------------------------------
HookReturnCode ClientPutInServer(CBasePlayer@ plr) {
  if (plr is null)
    return HOOK_CONTINUE;

  const int i = plr.entindex();

  g_lastFrags[i] = plr.pev.frags;
  g_nextHud[i] = 0.0f;

  return HOOK_CONTINUE;
}

// -----------------------------------------------------------------------------
HookReturnCode PlayerPostThink(CBasePlayer@ plr) {
  if (plr is null || !plr.IsConnected())
    return HOOK_CONTINUE;

  const int i = plr.entindex();

  const float frags = plr.pev.frags;
  const float delta = frags - g_lastFrags[i];
  if (delta > 0.0f)
    SetMoney(plr, GetMoney(plr) + delta);
  g_lastFrags[i] = frags;

  if (g_nextHud[i] > g_Engine.time)
    return HOOK_CONTINUE;

  g_nextHud[i] = g_Engine.time + HUD_UPDATE_INTERVAL;
  ShowMoneyHud(plr);

  return HOOK_CONTINUE;
}

// -----------------------------------------------------------------------------
void ShowMoneyHud(CBasePlayer@ plr) {
  HUDNumDisplayParams params;
  params.channel     = HUD_CHANNEL;
  params.flags       = HUD_ELEM_SCR_CENTER_X | HUD_ELEM_DEFAULT_ALPHA;
  params.value       = Math.Floor(float(GetMoney(plr)));
  params.defdigits   = 1;
  params.maxdigits   = 6;
  params.x           = HUD_POS_X;
  params.y           = HUD_POS_Y;
  params.color1      = RGBA(100, 130, 200, 255);
  params.fadeinTime  = 0.0f;
  params.fadeoutTime = 0.0f;
  params.holdTime    = HUD_UPDATE_INTERVAL + 0.2f;
  params.fxTime      = 0.0f;
  params.effect      = 0;

  g_PlayerFuncs.HudNumDisplay(plr, params);
}

// -----------------------------------------------------------------------------
HookReturnCode ClientSay(SayParameters@ pParams) {
  CBasePlayer@ plr = pParams.GetPlayer();
  if (plr is null)
    return HOOK_CONTINUE;

  const CCommand@ args = pParams.GetArguments();
  if (args.ArgC() >= 1 && args.Arg(0).ToLowercase() == OPEN_COMMAND) {
    pParams.ShouldHide = true;
    OpenAmmoMenu(plr);
  }

  return HOOK_CONTINUE;
}

// -----------------------------------------------------------------------------
void OpenAmmoMenu(CBasePlayer@ plr) {
  CTextMenu menu(@AmmoMenuCallback);
  menu.SetTitle("Buy ammo  (cash: " + int(GetMoney(plr)) + ")\n");

  for (uint i = 0; i < g_ammo.length(); i++) {
    if (g_PlayerFuncs.GetAmmoIndex(g_ammo[i].ammoName) < 0)
      continue;

    menu.AddItem(g_ammo[i].label + "  x" + g_ammo[i].amount + "  [$" + g_ammo[i].cost + "]",
                 any(g_ammo[i].ammoName));
  }

  menu.Register();
  menu.Open(0, 0, plr);

  @g_menus[plr.entindex()] = @menu;
}

// -----------------------------------------------------------------------------
void AmmoMenuCallback(CTextMenu@ menu, CBasePlayer@ plr, int iSlot, const CTextMenuItem@ item) {
  if (plr is null || item is null)
    return;

  string ammoName;
  item.m_pUserData.retrieve(ammoName);
  if (ammoName.IsEmpty())
    return;

  BuyAmmo(plr, ammoName);

  g_Scheduler.SetTimeout("ReopenAmmoMenu", 0.1f, plr.entindex());
}

// -----------------------------------------------------------------------------
void ReopenAmmoMenu(int idx) {
  CBasePlayer@ plr = g_PlayerFuncs.FindPlayerByIndex(idx);
  if (plr is null || !plr.IsConnected())
    return;

  OpenAmmoMenu(plr);
}

// -----------------------------------------------------------------------------
void BuyAmmo(CBasePlayer@ plr, const string& in ammoName) {
  if (plr is null || !plr.IsAlive())
    return;

  const int idx = FindAmmoIndex(ammoName);
  if (idx < 0)
    return;

  const int cost   = g_ammo[idx].cost;
  const int amount = g_ammo[idx].amount;

  const double money = GetMoney(plr);
  if (money < cost) {
    g_PlayerFuncs.SayText(plr, "[Buy Menu] You don't have enough cash.\n");
    return;
  }

  int maxAmmo = plr.GetMaxAmmo(ammoName);
  if (maxAmmo <= 0)
    maxAmmo = 999;

  const int given = plr.GiveAmmo(amount, ammoName, maxAmmo);

  if (given <= 0) {
    DropAmmo(plr, g_ammo[idx].entityName);
  }
  else {
    g_SoundSystem.PlaySound(plr.edict(), CHAN_ITEM, SOUND_AMMO_PICKUP, 1.0f, ATTN_NORM, 0, PITCH_NORM);
  }

  SetMoney(plr, money - cost);
}

// -----------------------------------------------------------------------------
void DropAmmo(CBasePlayer@ plr, const string& in entityName) {
  if (entityName.IsEmpty())
    return;

  dictionary keys;
  keys["origin"] = plr.pev.origin.ToString();

  CBaseEntity@ item = g_EntityFuncs.CreateEntity(entityName, keys, false);
  if (item is null)
    return;

  item.pev.spawnflags |= SF_NORESPAWN;
  g_EntityFuncs.DispatchSpawn(item.edict());
}

// -----------------------------------------------------------------------------
int FindAmmoIndex(const string& in ammoName) {
  for (uint i = 0; i < g_ammo.length(); i++) {
    if (g_ammo[i].ammoName == ammoName)
      return int(i);
  }
  return -1;
}

// --- Moneda ------------------------------------------------------------------
double GetMoney(CBasePlayer@ plr) {
  if (plr is null)
    return 0;

  const string id = g_EngineFuncs.GetPlayerAuthId(plr.edict());
  double m = 0;
  if (g_money.exists(id))
    g_money.get(id, m);

  return m;
}

void SetMoney(CBasePlayer@ plr, double amount) {
  if (plr is null)
    return;

  if (amount < 0)
    amount = 0;

  const string id = g_EngineFuncs.GetPlayerAuthId(plr.edict());
  g_money[id] = amount;
}