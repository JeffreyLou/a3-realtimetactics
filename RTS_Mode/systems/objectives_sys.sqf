#include "../RTS_defines.hpp"

private _objectiveTypes = [
							"occupy",  		// Must keep units on objective with no enemy presence
							"clear",   		// Remove all enemy units from an area
							"touch",   		// Friendly unit must reach this area
							"destroy", 		// Destroy all vehicles that start within the marker
							"clear_nomark"  // Do not show a marker for the clear objective, just the center of the task
						];

objectiveInitialColor = {
	params ["_side"];
	
	private _ret = [];
	
	switch ( _side ) do {
		case west: {
			_ret = "ColorRed";
		};
		case east: {
			_ret = "ColorBlue";
		};
		case resistance: {
			_ret = [RTS_Greenfor_Enemy] call objectiveInitialColor;
		};
	};
	
	_ret
};

objectiveDescription = {
	params ["_type"];
	
	private _desc = [];
	
	switch ( _type )  do {
		case "occupy": {
			_desc = "Secure the location. Keep friendly units in the area and repel enemy forces to hold the objective.";
		};
		case "clear": {
			_desc = "Remove all enemy presence from the location, do not allow them to return.";
		};
		case "touch": {
			_desc = "Reach this position with any units.";
		};
		case "destroy": {
			_desc = "Destroy all vehicles indicated. Not implemented!";
		};
		case "clear_nomark": {
			_desc = "Remove all enemy presence from the location.";
		};
	};
};

RTS_missionFinished = false;

RTS_missionAccomplished = {
	RTS_missionFinished
};

publicVariable "RTS_missionFinished";
publicVariable "RTS_missionAccomplished";

private _objectives = [];

{
	private _i = 1;
	private _j = 1;
	private _mark = format ["%1_objective_%2_%3", _x, _i, _j];
	(getMarkerSize _mark) params ["_mx", "_my"];
	while { _i < 10 } do {
		while { _mx + _my != 0 } do {	
			_mark setMarkerAlphaLocal 0;
			
			// Create objective marker
			private _newmark = (str (side player)) + _mark;
			private _objText = markerText _mark;
			createMarker [_newmark, getMarkerPos _mark];
			_newMark setMarkerAlpha 1;
			_newMark setMarkerShape (markerShape _mark);
			_newMark setMarkerBrush (markerBrush _mark);
			_newMark setMarkerSize (markerSize _mark);
			_newMark setMarkerDir (markerDir _mark);
			_newMark setMarkerColor ([(side player)] call objectiveInitialColor);
			
			_objectives pushBack ( [_x, _newMark, _objText, false] );
			
			_j = _j + 1;
			_mark = format ["%1_objective_%2_%3", _x, _i, _j];
			_mx = (getMarkerSize _mark) select 0;
			_my = (getMarkerSize _mark) select 1;
		};
		_i = _i + 1;
		_j = 1;
		_mark = format ["%1_objective_%2_%3", _x, _i, _j];
		_mx = (getMarkerSize _mark) select 0;
		_my = (getMarkerSize _mark) select 1;
	};
} forEach _objectiveTypes;

waitUntil { RTS_setupComplete };

// Create side tasking
for "_i" from 0 to ( (count _objectives) - 1 ) do {
	(_objectives select _i) params ["_type","_marker","_name"];

	private _taskName = format ["%1%2", _type, _i];

	[ RTS_sidePlayer, [_taskName], [ [_type] call objectiveDescription, _name, _marker ], getMarkerPos _marker, "CREATED" ] call BIS_fnc_taskCreate;
	
	(_objectives select _i) pushback _taskName;
	
	sleep 5;
};

RTS_objectiveLoop = [_objectives] spawn {
	params ["_objectives"];
	
	// Do objective logic here
	
	while { true } do {
		{
			_x params ["_type", "_marker", "", "_completed", "_taskName"];
				
			switch ( _type ) do {
				case "occupy": {
					private _enemy = allUnits select { alive _x && side _x == RTS_sideEnemy };
					private _friendly = allUnits select { alive _x && side _x == RTS_sidePlayer };
					private _inareaEnemy = _enemy select { (getPos _x) inArea _marker };
					private _inareaFriendly = _friendly select { (getPos _x) inArea _marker };
					
					if ( !_completed && count _inareaEnemy == 0 && count _inareaFriendly > 0 ) then {
						[_taskName, "SUCCEEDED"] call BIS_fnc_taskSetState;
						_marker setMarkerColor ([RTS_sideEnemy] call objectiveInitialColor);
						_x set [3, true];
					} else {
						if ( _completed && count _inareaEnemy > 0 && count _inareaFriendly < 1) then {
							[_taskName, "CREATED"] call BIS_fnc_taskSetState;
							_marker setMarkerColor ([RTS_sidePlayer] call objectiveInitialColor);
							_x set [3, false];
						};
					};
					
				};
				case "clear": {
					private _enemy = allUnits select { alive _x && side _x == RTS_sideEnemy };
					private _inareaEnemy = _enemy select { (getPos _x) inArea _marker };
					private _friendly = allUnits select { alive _x && side _x == RTS_sidePlayer };
					private _inareaFriendly = _friendly select { (getPos _x) inArea _marker };
					
					if ( !_completed && count _inareaEnemy == 0 && count _inareaFriendly > 0) then {
						[_taskName, "SUCCEEDED"] call BIS_fnc_taskSetState;
						_marker setMarkerColor ([RTS_sideEnemy] call objectiveInitialColor);
						_x set [3, true];
					} else {
						if ( _completed && count _inareaEnemy > 0 ) then {
							[_taskName, "CREATED"] call BIS_fnc_taskSetState;
							_marker setMarkerColor ([RTS_sidePlayer] call objectiveInitialColor);
							_x set [3, false];
						};
					};

				};
				case "touch": {
					if ( !_completed ) then {
						private _friendly = allUnits select { alive _x && side _x == RTS_sidePlayer };
						private _inarea = _friendly select { (getPos _x) inArea _marker };
						
						if ( count _inarea > 0 ) then {
							_x set [3, true];
							[_taskName, "SUCCEEDED"] call BIS_fnc_taskSetState;
							_marker setMarkerColor ([RTS_sideEnemy] call objectiveInitialColor);
							_x set [3, true];
						};
					};
				};
			};
			
		} forEach _objectives;
		
		private _allComplete = true;
		{
			_x params ["","","","_completed"];
			_allComplete = _allComplete && _completed;
		} forEach _objectives;
		
		if ( _allComplete ) then {
			RTS_missionFinished = true;
			publicVariable "RTS_missionFinished";
		} else {
			RTS_missionFinished = false;
			publicVariable "RTS_missionFinished";
		};
	};
};
