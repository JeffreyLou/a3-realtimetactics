#include "\z\ace\addons\spectator\script_component.hpp"
#include "\A3\ui_f\hpp\defineDIKCodes.inc"
#include "RTS_defines.hpp"

_east = createCenter east;
_west = createCenter west;
_resist = createCenter resistance;
_civ = createCenter civilian;

mapAnimAdd [0, 0.1, getMarkerPos "map_center"];
mapAnimCommit;

RTS_setupScripts = [];

setGroupIconsVisible [true, false];

// Function for creating function setups
RTS_setupFunction = {
	params ["_prefix", "_functions"];
	RTS_setupScripts pushBackUnique (_prefix + "\setup.sqf");
	{
		private _split = _x splitString "_";
		private _head = _split select 0;
		private _filename = [];
		for "_i" from 1 to ((count _split)-1) do {
			_filename set [count _filename, _split select _i];
		};
		_filename = _filename joinString "_";
		private _code = (format ["%1_%2 = compile preprocessFileLineNumbers ""%3\%2.sqf"";", _head, _filename, _prefix]);
		call (compile _code);
	} forEach _functions;
};

RTS_rerunAllSetups = {
	{
		[] call (compile preprocessFileLineNumbers _x);
	} forEach RTS_setupScripts;
};

[] call (compile preprocessFileLineNumbers "rts\functions\shared\setup.sqf");

_initserver = [] spawn (compile preprocessFileLineNumbers "rts\initServer.sqf");

waitUntil { scriptDone _initserver };

if ( isDedicated || !hasInterface ) exitWith {};

[] call (compile preprocessFileLineNumbers "rts\functions\client\setup.sqf");

[] call RTS_fnc_hideAllMarkers;

[] execVM "rts\initPlayer.sqf";

waitUntil { !(isNull player) && isPlayer player };
waitUntil { time > 1 };

setGroupIconsVisible [false, false];

makeVehicleSafe = {
	private _veh = _this select 0;
	private _side = side _veh;
	{
		if ( side _x == _side && !(isPlayer _x) ) then {
			_veh disableCollisionWith _x;
		};
	} forEach allUnits;
};
disableFriendlyCollision = {
	{
		if ( !( _x isKindOf "StaticWeapon" ) && !( _x isKindOf "EmptyDetector" ) ) then {
			[_x] call makeVehicleSafe;
		};
	} forEach vehicles;
};

call disableFriendlyCollision;

RTS_safeVehicleThread = [] spawn {
	while { true } do {
		call disableFriendlyCollision;
		sleep 30;
	};
};

if ( !([] call RTS_fnc_isCommander) ) exitWith {};

[] call (compile preprocessFileLineNumbers "rts\ace_spectator_overrides\setup.sqf");
[] call (compile preprocessFileLineNumbers "rts\functions\client\commander\setup.sqf");

if ( side player == west ) then {
	RTS_deploymentMarks = ["blufor"] call RTS_fnc_getAllDeploymentMarkers;
	RTS_aoMarker = "blufor_ao";
	RTS_camStart = "blufor_start";
	RTS_camTarget = "blufor_target";
	RTS_sidePlayer = west;
	RTS_sideEnemy = east;
	RTS_sideGreen = resistance;
	RTS_sideColor = [0.25,0.25,1,1];
	RTS_enemyColor = [1,0.25,0.25,1];
	RTS_greenColor = [0.25,1,0.25,1];
} else {
	if ( side player == east ) then  {
		RTS_deploymentMarks = ["opfor"] call RTS_fnc_getAllDeploymentMarkers;
		RTS_aoMarker = "opfor_ao";
		RTS_camStart = "opfor_start";
		RTS_camTarget = "opfor_target";
		RTS_sidePlayer = east;
		RTS_sideEnemy = west;
		RTS_sideGreen = resistance;
		RTS_sideColor = [1,0.25,0.25,1];
		RTS_enemyColor = [0.25,0.25,1,1];
		RTS_greenColor = [0.25,1,0.25,1];
	} else {
		RTS_deploymentMarks = ["greenfor"] call RTS_fnc_getAllDeploymentMarkers;
		RTS_aoMarker = "greenfor_ao";
		RTS_camStart = "greenfor_start";
		RTS_camTarget = "greenfor_target";
		RTS_sidePlayer = resistance;
		RTS_sideEnemy = RTS_Greenfor_Enemy;
		RTS_sideGreen = RTS_Greenfor_Green;
		RTS_sideColor = [0.25,1,0.25,1];
		RTS_enemyColor = RTS_Greenfor_EnemyColor;
		RTS_greenColor = RTS_Greenfor_GreenColor;
	};
};

RTS_canPause = if ( isServer ) then { true } else { false };
RTS_casualtyColor = [0.8,0.8,0,1];
RTS_brokenColor = [0.3,0.3,0.3,0.8];
RTS_commandAction = -1;
RTS_paused = false;
RTS_pausing = false;
RTS_initialMen = 0;
RTS_initialWeapons = 0;
RTS_initialVehicles = 0;
RTS_casualties = 0;

// Start in the deployment phase
RTS_phase = "DEPLOY";
RTS_selecting = false;
RTS_selectStart = [];
RTS_backspace = false;
RTS_formationChoose = false;
RTS_combatChoose = false;
RTS_stanceChoose = false;
RTS_buildingposChoose = false;
RTS_issuingPause = false;
RTS_command = nil;
RTS_commanding = false;
RTS_commandingGroups = [];
RTS_opfor_vehicles = [];
RTS_greenfor_vehicles = [];
RTS_selectedGroup = grpnull;
RTS_fakeCameraTarget = "Land_HandyCam_F" createVehicleLocal [0,0,0];
RTS_fakeCameraTarget hideObject true;
RTS_groupIconMaxDistance = 1500;
RTS_briefingComplete = false;
RTS_helpKey = false;
RTS_showHelp = false;
RTS_missionFailLimit = if ( RTS_timeLimit > 0 ) then { RTS_timeLimit } else { nil };
RTS_objectivesSetupDone = false;

// RTS Specific Commands
[] call (compile preprocessFileLineNumbers "rts\commands\setup.sqf");
[] spawn (compile preprocessFileLineNumbers "rts\systems\commander_sys.sqf");
[] spawn (compile preprocessFileLineNumbers "rts\systems\spotting_system.sqf");
RTS_ui = [] spawn (compile preprocessFileLineNumbers "rts\systems\ui_system.sqf");
RTS_reinforce = [] spawn (compile preprocessFileLineNumbers "rts\systems\reinforcements.sqf");
[] spawn (compile preprocessFileLineNumbers "rts\systems\objectives_sys.sqf");

// Reveal dead stuff
{
	(vehicle _x) hideObject true;
	_x addEventHandler [ "killed", { (_this select 0) hideObject false; (vehicle (_this select 0)) hideObject false; } ];
} forEach (allunits select { side _x != RTS_sidePlayer } );


{
	_x addEventHandler ["killed", 
						{
							params ["","_killer"];
							private _group = group _killer;
							if ( side _group == RTS_sidePlayer && _group in RTS_commandingGroups ) then {
								_group setVariable ["combat_victories", (_group getVariable ["combat_victories", 0]) + 1];
							};							
						}];
} forEach (allunits select { side _x != RTS_sidePlayer } );

RTS_setupComplete = false;

if ( !RTS_skipBriefing ) then {
	[] execVm "rts\briefing\presentMissionToCommander.sqf";
	waitUntil { RTS_briefingComplete };
};

[] spawn {


if ( isNil "RTS_commandObject" ) then {
	RTS_commandObject = player;
};

RTS_commandObject addAction ["Begin Commanding", 
	{
		if ( scriptDone RTS_ui ) then {
			RTS_ui = [] spawn (compile preprocessFileLineNumbers "rts\systems\ui_system.sqf");
		};
		
		RTS_commanderUnit = player;
		[true] call ace_spectator_fnc_cam;
		[true] call RTS_fnc_ui;
		RTS_setupComplete = true;
		
		[0,
		{
			_this call RTS_fnc_setupCommander
		},[player]] call CBA_fnc_globalExecute;
	}];

waitUntil { RTS_setupComplete };

RTS_mapHandling = [] spawn (compile preprocessFileLineNumbers "rts\systems\map_handling.sqf");

RTS_killedEH = player addEventHandler ["killed", {
	private _pos = getPosATL player;
	private _dir = getDir player;
	_pos set [2, 5];
	private _leader = ((units (group player)) select { alive _x }) select 0;
	(group player) selectLeader _leader;
	(units (group player)) doFollow _leader;
	RTS_ui = [] spawn (compile preprocessFileLineNumbers "rts\systems\ui_system.sqf");
	player removeAction RTS_commandAction;
	player removeEventHandler ["killed", RTS_killedEH];
	selectPlayer RTS_commanderUnit;
	[true] call ace_spectator_fnc_cam;
	[true] call RTS_fnc_ui;
	ace_spectator_camera setPosATL _pos;
	ace_spectator_camera setDir _dir;
}];

[] call RTS_fnc_setupAllGroups;

{

	_group = _x;
	
	// VCOM Stuff
	_group setVariable ["VCM_NOFLANK",true];
	_group setVariable ["VCM_DisableForm",true];
	_group setVariable ["VCM_NORESCUE",true];
	_group setVariable ["VCM_TOUGHSQUAD",true];
	
	if ( (vehicle (leader _group)) == (leader _group) ) then {
		{ 
			_x disableAi "AUTOCOMBAT";
		} forEach (units _group);
	};
	
	_group enableAttack false;
	{
		_x allowFleeing 0;
		_x disableAi "FSM";
		addSwitchableUnit _x;
	} forEach (units _group);
} forEach RTS_commandingGroups;


[] spawn (compile preprocessFileLineNumbers "rts\systems\radio_communications.sqf");

// temporary group monitor
RTS_groupMon = {
		private _group = RTS_selectedGroup;
		_commanderinfo = format
			["COMBAT OVERVIEW<br/><br/><t align='left'>Initial Strength:</t><t align='right'>%1</t><br/><t align='left'>Initial Weapons:</t><t align='right'>%2</t><br/><t align='left'>Initial Vehicles:</t><t align='right'>%3</t><br/><t align='left'>Casualties:</t><t align='right'>%4</t>", 
				RTS_initialMen,
				RTS_initialWeapons,
				RTS_initialVehicles,
				RTS_casualties];
		
		if ( RTS_timeLimit > 0 ) then {
			_commanderinfo = _commanderinfo + (format ["<br/><t align='left'>Time Limit:</t><t align='right'>%1</t>", [RTS_timeLimit, "HH:MM"] call BIS_fnc_secondsToString ]);
		};
		
		if ( RTS_debug ) then {
			private _opforUnits = allUnits select { alive _x && side _x == RTS_sideEnemy };	
			_commanderinfo = _commanderinfo + (format ["<br/><t align='left'>Opfor Strength:</t><t align='right'>%1</t>", count _opforUnits ]);
		};
					
		// Controls information
		_name = "";
		_additional = "";
		if ( ! isNil "RTS_command" ) then { 
			RTS_command params ["_one","","","_three"];
			if !(isNil "_one") then { _name = "<br/><br/>" + _one };
			if !(isNil "_three") then { _additional = "<br/><br/>" + _three };
		};
		
		private _helptext =
		"<t size='1.1'>Click and Drag, or Double Click on a soldier/vehicle to select a unit<br/><br/>" +
		"Hold Buttons and double click to assign an order to a unit<br/><br/></t>" +
		"<t align='left' size='1'>E -</t><t align='right'>Move</t>" + "<br/>" +
		"<t align='left' size='1'>Shift+E -</t><t align='right'>Fast Move</t>" + "<br/>" +
		"<t align='left' size='1'>Ctrl+E -</t><t align='right'>Careful Move</t>" + "<br/>" +
		"<t align='left' size='1'>R -</t><t align='right'> &#160;Mount/Dismount Crew</t>" + "<br/>" +
		"<t align='left' size='1'>T -</t><t align='right'>Watch Position</t>" + "<br/>" +
		"<t align='left' size='1'>Shift+T -</t><t align='right'>Check Position Visibility</t>" + "<br/>" +
		"<t align='left' size='1'>X -</t><t align='right'>Enter Building</t>" + "<br/>" +
		"<t align='left' size='1'>Space -</t><t align='right'>Load/Unload Passengers</t>" + "<br/>" +
		"<t align='left' size='1'>F -</t><t align='right'>Select Formation</t>" + "<br/>" +
		"<t align='left' size='1'>V -</t><t align='right'>Select Stance</t>" + "<br/>" +
		"<t align='left' size='1'>C -</t><t align='right'>Select Combat Mode</t>" + "<br/>" +
		"<t align='left' size='1'>` -</t><t align='right'>Control Unit</t>" + "<br/>" +
		"<t align='left' size='1'>Backspace -</t><t align='right'>Delete Last Order</t>" + "<br/>" +
		"<t align='left' size='1'>P -</t><t align='right'>Add Wait time to Last Order</t>" + "<br/>" +
		"<t align='left' size='1'>Tab -</t><t align='right'>Pause</t>";
		
		_controlinfo = format ["Press H For Command List<br/><br/>NEXT COMMAND%1%2", _name, _additional];
		hintSilent (parseText (format ["%1<br/><br/>%2<br/><br/>%3",_commanderinfo, _controlinfo, ( if ( RTS_showHelp ) then { _helptext } else { "" } ) ]));
};

RTS_ai_system = compile preprocessFileLineNumbers "rts\systems\ai_command_processing.sqf";
RTS_processingThread = addMissionEventHandler ["Draw3D", { call RTS_ai_system }];
// Update status info on every frame (for now, will use proper UI eventually)
RTS_monitorHandler = addMissionEventHandler ["Draw3D", { if ( RTS_commanding ) then { call RTS_groupMon }; }];

};