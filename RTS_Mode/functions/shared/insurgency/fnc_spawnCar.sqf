params ["_pos","_side","_exact"];

private _nosetup = false;

if ( isNil "_side" ) then {
	_side = east;
} else {
	_nosetup = true;
};

if ( isNil "_exact" ) then {
	private _radius = 150;
	private _players = (call INS_allPlayers) select { side _x != _side };
	private _enemies = ( if ( _side != civilian ) then { allUnits select { side _x != civilian && side _x != _side } } else { [] } ) + _players;
	while { !(isOnRoad _pos) || count ([_pos, _enemies,800] call CBA_fnc_getNearest) > 0 } do {
		private _roads = _pos nearRoads _radius;
		if ( count _roads > 0 ) then {
			_pos = (getPos (selectRandom _roads));
		} else {
			_radius = _radius + 100;
		};
	};
};

private _soldier = [_pos,nil,_side] call INS_fnc_spawnRandomSoldier;

private _type = (INS_carClasses call BIS_fnc_selectRandom);
private _carpos = (_pos findEmptyPosition [0,50,_type]);
private _car = _type createVehicle _carpos;
_car setVectorUp (surfaceNormal _carpos);

private _grp = group _soldier;
[units _grp] allowGetIn true;
_soldier assignAsDriver _car;
_soldier moveInDriver _car;	

if ( !_nosetup ) then {
	_grp setVariable ["RTS_setup", [_grp, getText (configFile >> "CfgVehicles" >> _type >> "displayName"), grpnull, "\A3\ui_f\data\map\markers\nato\o_motor_inf.paa", "o_motor_inf"],true];
};

_soldier