//---------------------------------------------------------------------------------------
//  FILE:    X2AchievementTracker.uc
//  AUTHOR:  Aaron Smith -- 7/29/2015
//  PURPOSE: Tracks achievements
//           
//---------------------------------------------------------------------------------------
//  Copyright (c) 2016 Firaxis Games, Inc. All rights reserved.
//---------------------------------------------------------------------------------------
class X2AchievementTracker extends Object
	native(Core);

var TDateTime	GameStartTime;
var TDateTime	June1st;
var TDateTime	July1st;
var TDateTime	July31st;

enum HeavyWeaponKill
{
	HWK_RocketLauncher,
	HWK_ShredderGun,
	HWK_Flamethrower,
	HWK_HellfireProjector,
	HWK_BlasterLauncher,
	HWK_PlasmaBlaster,
	HWK_ShredstormCannon,
};

var array<Name> arrSkulljackedUnitGroups;

native function Init();

// Singleton creation / access of the XComGameState_AchievementData.  Pass in a NewGameState if the
// method you're calling from this takes one, otherwise don't.
static function XComGameState_AchievementData GlobalAchievementData(optional XComGameState NewGameState = none)
{
	local XComGameState_AchievementData AchievementData;

	AchievementData = XComGameState_AchievementData(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_AchievementData', true));
	if (AchievementData == none)
	{
		if (NewGameState == none)
		{
			NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Create AchievementData singleton");
			AchievementData = XComGameState_AchievementData(NewGameState.CreateStateObject(class'XComGameState_AchievementData'));

			NewGameState.AddStateObject(AchievementData);
			`TACTICALRULES.SubmitGameState(NewGameState);
		}
		else
		{
			AchievementData = XComGameState_AchievementData(NewGameState.CreateStateObject(class'XComGameState_AchievementData'));
			NewGameState.AddStateObject(AchievementData);
		}
	}

	return AchievementData;
}

event OnInit()
{
	class'X2StrategyGameRulesetDataStructures'.static.SetTime(
		GameStartTime, 0, 0, 0,
		class'X2StrategyGameRulesetDataStructures'.default.START_MONTH, 
		class'X2StrategyGameRulesetDataStructures'.default.START_DAY, 
		class'X2StrategyGameRulesetDataStructures'.default.START_YEAR
	);

	class'X2StrategyGameRulesetDataStructures'.static.SetTime(
		June1st, 0, 0, 0,
		6, 1,
		class'X2StrategyGameRulesetDataStructures'.default.START_YEAR
	);

	class'X2StrategyGameRulesetDataStructures'.static.SetTime(
		July1st, 0, 0, 0,
		7, 1,
	class'X2StrategyGameRulesetDataStructures'.default.START_YEAR
		);

	class'X2StrategyGameRulesetDataStructures'.static.SetTime(
		July31st, 0, 0, 0,
		7, 31,
		class'X2StrategyGameRulesetDataStructures'.default.START_YEAR
	);

	arrSkulljackedUnitGroups.Length = 0;

	arrSkulljackedUnitGroups.AddItem('AdventTrooper');
	arrSkulljackedUnitGroups.AddItem('AdventCaptain');
	arrSkulljackedUnitGroups.AddItem('AdventShieldBearer');
	arrSkulljackedUnitGroups.AddItem('AdventStunLancer');
	arrSkulljackedUnitGroups.AddItem('Cyberus');

	`XPROFILESETTINGS.Data.arrbSkulljackedUnits.Length = arrSkulljackedUnitGroups.Length;
}

// Catches the end of a mission
static function EventListenerReturn OnTacticalGameEnd(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	local XComGameState NewGameState;
	local XComGameState_AchievementData AchievementData;
	local XComGameState_BattleData Battle;
	local XComGameState_CampaignSettings Settings;
	local XComGameStateHistory History;
	local XComGameState_Unit Unit;
	local XComGameState_Unit LastUnit;
	local bool AllRookies;
	local int NumCivilianDeaths;
	local bool JuneOrLater;
	local bool SameClass;

	if (GameState.GetContext().InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}

	History = `XCOMHISTORY;
	Settings = XComGameState_CampaignSettings(History.GetSingleGameStateObjectForClass(class'XComGameState_CampaignSettings'));
	Battle = XComGameState_BattleData(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_BattleData'));
	AchievementData = GlobalAchievementData();

	`log("XComGameState_AchievementTracker.OnTacticalGameEnd");

	// Make sure the player won
	if (!(Battle.bLocalPlayerWon && !Battle.bMissionAborted))
	{
		return ELR_NoInterrupt;
	}

	// Beat the game. 
	// (According to Nauta, FinalMissionOnSuccess is called when the game returns to the shell - 
	//  which may not happen given the current game flow.  Calling FinalMissionOnSuccess here is a 
	//  just in case measure.)
	if (string(Battle.MapData.ActiveMission.MissionName) == "AssaultAlienFortress")
	{
		FinalMissionOnSuccess();
	}

	// Sabotage an alien facility
	if (string(Battle.MapData.ActiveMission.MissionName) == "SabotageAlienFacility")
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_SabotageFacility);
	}

	// Recover the Forge Item
	if (string(Battle.MapData.ActiveMission.MissionName) == "AdventFacilityFORGE")
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_RecoverForgeItem);
	}

	// Recover the Psi Gate
	if (string(Battle.MapData.ActiveMission.MissionName) == "AdventFacilityPSIGATE")
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_RecoverPsiGate);
	}
	
	// Recover the Black Site Data
	if (string(Battle.MapData.ActiveMission.MissionName) == "AdventFacilityBLACKSITE")
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_RecoverBlackSiteData);
	}

	// Recover a Codex Brain
	// Once in the mission use "DropUnit Cyberus 1 False". Then kill it and finish the mission.
	// Only applicable in the single-player campaign (not MP, not challenge mode)
	if (AchievementData.bKilledACyberusThisMission && `XENGINE.IsSinglePlayerGame() && !(`ONLINEEVENTMGR.bIsChallengeModeGame))
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_RecoverCodexBrain);
	}

	// Beat a Retaliation mission with less than 4 civilian deaths
	if (string(Battle.MapData.ActiveMission.MissionName) == "Terror")
	{
		NumCivilianDeaths = 0;
		foreach History.IterateByClassType(class'XComGameState_Unit', Unit)
		{
			if (Unit.IsCivilian() && Unit.IsDead())
			{
				NumCivilianDeaths++;
			}
		}

		if (NumCivilianDeaths <= 3)
		{
			`ONLINEEVENTMGR.UnlockAchievement(AT_BeatMissionNoCivilianDeath);
		}
	}
	
	// Check for AT_BeatMissionJuneOrLater - Beat a mission in June or later using only Rookies
	AllRookies = true;
	foreach History.IterateByClassType(class'XComGameState_Unit', Unit)
	{
		if (Unit.IsPlayerControlled() && Unit.IsSoldier())
		{
			if (Unit.GetSoldierRank() != 0)
			{
				AllRookies = false;
				break;
			}
		}
	}

	JuneOrLater = class'X2StrategyGameRulesetDataStructures'.static.LessThan(`XACHIEVEMENT_TRACKER.June1st, Battle.LocalTime);
	if (JuneOrLater && AllRookies) // Beat a mission in June or later using only Rookies
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_BeatMissionJuneOrLater);
	}

	// Check for AT_BeatMissionSameClass - Beat a mission on Classic+ with a squad composed entirely of soldiers of the same class (but not rookie)
	SameClass = false;
	if (!AllRookies)
	{
		LastUnit = none;
		foreach History.IterateByClassType(class'XComGameState_Unit', Unit)
		{
			if (Unit.IsPlayerControlled() && Unit.IsSoldier())
			{
				if (LastUnit != none)
				{
					SameClass = true; // There must be at least two units for "same" to apply

					// Each unit must have the same class as the last unit for the condition to be true
					if (Unit.GetSoldierClassTemplate() != LastUnit.GetSoldierClassTemplate())
					{
						SameClass = false;
						break;
					}
				}
				LastUnit = Unit;
			}
		}
	}

	if (Settings.LowestDifficultySetting >= 2 && SameClass) // Beat a mission on Commander or harder with a squad composed entirely of soldiers of the same class (but not rookie)
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_BeatMissionSameClass);
	}

	// Clear the bKilledACyberusThisMission boolean
	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("X2AchievementTracker.OnTacticalGameEnd");
	AchievementData = XComGameState_AchievementData(NewGameState.CreateStateObject(class'XComGameState_AchievementData', AchievementData.ObjectID));

	AchievementData.bKilledACyberusThisMission = false;

	NewGameState.AddStateObject(AchievementData);
	`TACTICALRULES.SubmitGameState(NewGameState);


	return ELR_NoInterrupt;
}

// This is called at the start of each turn
static function EventListenerReturn OnPlayerTurnBegun(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	local XComGameState NewGameState;
	local XComGameState_AchievementData AchievementData;

	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}

	// We only care about the human player's turn, not the AI's
	if (`TACTICALRULES.GetLocalClientPlayerObjectID() != XComGameState_Player(EventSource).ObjectID)
		return ELR_NoInterrupt;

	AchievementData = GlobalAchievementData();
	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("X2AchievementTracker.OnTurnBegun");
	AchievementData = XComGameState_AchievementData(NewGameState.CreateStateObject(class'XComGameState_AchievementData', AchievementData.ObjectID));

	AchievementData.arrKillsPerUnitThisTurn.Length = 0;

	NewGameState.AddStateObject(AchievementData);
	`TACTICALRULES.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

// This is called at the end of each turn
static function EventListenerReturn OnPlayerTurnEnded(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	local XComGameState NewGameState;
	local XComGameState_AchievementData AchievementData;

	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}
	
	// We only care about the human player's turn, not the AI's
	if (`TACTICALRULES.GetLocalClientPlayerObjectID() != XComGameState_Player(EventSource).ObjectID)
		return ELR_NoInterrupt;

	AchievementData = GlobalAchievementData();
	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("X2AchievementTracker.OnPlayerTurnEnded");
	AchievementData = XComGameState_AchievementData(NewGameState.CreateStateObject(class'XComGameState_AchievementData', AchievementData.ObjectID));
		
	AchievementData.arrKillsPerUnitThisTurn.Length = 0;
	AchievementData.arrRevealedUnitsThisTurn.Length = 0;
	AchievementData.arrUnitsKilledThisTurn.Length = 0;	
	
	NewGameState.AddStateObject(AchievementData);
	`TACTICALRULES.SubmitGameState(NewGameState);

	return ELR_NoInterrupt;
}

// This is called every time an enemy is killed
static function EventListenerReturn OnKillMail(Object EventData, Object EventSource, XComGameState NewGameState, Name EventID)
{
	local XComGameState_AchievementData AchievementData;
	local XComGameState_Unit SourceUnit;
	local XComGameState_Unit KilledUnit;
	local int i;
	local UnitKills NewUnitKill;
	local bool found;

	if (NewGameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}

	SourceUnit = XComGameState_Unit(EventSource);
	KilledUnit = XComGameState_Unit(EventData);

 	AchievementData = GlobalAchievementData();

	// Achievement: Kill 3 enemies in a single turn, with a single soldier, without explosives
	if (`XENGINE.IsSinglePlayerGame())
	{
		if (SourceUnit.IsEnemyUnit(KilledUnit) && !KilledUnit.bKilledByExplosion) //Don't count friendly-fire or explosive kills
		{
			found = false;
			for (i = 0; i < AchievementData.arrKillsPerUnitThisTurn.Length; i++)
			{
				if (AchievementData.arrKillsPerUnitThisTurn[i].UnitId == SourceUnit.ObjectID)
				{
					AchievementData.arrKillsPerUnitThisTurn[i].NumKills++;
					if (SourceUnit.IsPlayerControlled() && AchievementData.arrKillsPerUnitThisTurn[i].NumKills == 3) //Achievement can only trigger on player-controlled units
					{
						`ONLINEEVENTMGR.UnlockAchievement(AT_TripleKill);
					}

					found = true;
					break;
				}
			}

			if (!found)
			{
				NewUnitKill.UnitID = SourceUnit.ObjectID;
				NewUnitKill.NumKills = 1;

				NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("X2AchievementTracker.OnPlayerTurnEnded");
				AchievementData = XComGameState_AchievementData(NewGameState.CreateStateObject(class'XComGameState_AchievementData', AchievementData.ObjectID));

				AchievementData.arrKillsPerUnitThisTurn.AddItem(NewUnitKill);

				NewGameState.AddStateObject(AchievementData);
				`TACTICALRULES.SubmitGameState(NewGameState);
			}
		}

		// Achievement: Kill 500 aliens (does not have to be in same game)
		if ( SourceUnit.IsPlayerControlled() && SourceUnit.IsEnemyUnit(KilledUnit) && (KilledUnit.IsAlien() || KilledUnit.IsAdvent()) )
		{
			`XPROFILESETTINGS.Data.m_iGlobalAlienKills++;

			if (`XPROFILESETTINGS.Data.m_iGlobalAlienKills >= 500)
				`ONLINEEVENTMGR.UnlockAchievement(AT_Kill500);

			`ONLINEEVENTMGR.SaveProfileSettings();
		}
	}

	return ELR_NoInterrupt;
}

static function EventListenerReturn OnWeaponKillType(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	local XComGameState_Ability Ability;
	local XComGameState_Item Item;
	local name TemplateName;
	local XComGameStateHistory History;	

	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}

	Ability = XComGameState_Ability(EventData);

	History = `XCOMHISTORY;
	Item = XComGameState_Item(History.GetGameStateForObjectID(Ability.SourceWeapon.ObjectID));
	TemplateName = Item.GetMyTemplateName();

	switch (TemplateName)
	{
	case 'RocketLauncher':
		`XPROFILESETTINGS.Data.m_HeavyWeaponKillMask = `XPROFILESETTINGS.Data.m_HeavyWeaponKillMask | (0x1 << HWK_RocketLauncher);
		break;

	case 'ShredderGun':
		`XPROFILESETTINGS.Data.m_HeavyWeaponKillMask = `XPROFILESETTINGS.Data.m_HeavyWeaponKillMask | (0x1 << HWK_ShredderGun);
		break;

	case 'Flamethrower':
		`XPROFILESETTINGS.Data.m_HeavyWeaponKillMask = `XPROFILESETTINGS.Data.m_HeavyWeaponKillMask | (0x1 << HWK_Flamethrower);
		break;

	case 'FlamethrowerMk2':
		`XPROFILESETTINGS.Data.m_HeavyWeaponKillMask = `XPROFILESETTINGS.Data.m_HeavyWeaponKillMask | (0x1 << HWK_HellfireProjector);
		break;

	case 'BlasterLauncher':
		`XPROFILESETTINGS.Data.m_HeavyWeaponKillMask = `XPROFILESETTINGS.Data.m_HeavyWeaponKillMask | (0x1 << HWK_BlasterLauncher);
		break;

	case 'PlasmaBlaster':
		`XPROFILESETTINGS.Data.m_HeavyWeaponKillMask = `XPROFILESETTINGS.Data.m_HeavyWeaponKillMask | (0x1 << HWK_PlasmaBlaster);
		break;

	case 'ShredstormCannon':
		`XPROFILESETTINGS.Data.m_HeavyWeaponKillMask = `XPROFILESETTINGS.Data.m_HeavyWeaponKillMask | (0x1 << HWK_ShredstormCannon);
		break;
	}
	
	// Achievement: Kill an enemy with every heavy weapon in the game (Doesn't have to be in the same game)
	if (`XPROFILESETTINGS.Data.m_HeavyWeaponKillMask == ((0x1 << HeavyWeaponKill.EnumCount) - 1))
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_KillWithEveryHeavyWeapon);
	}

	`ONLINEEVENTMGR.SaveProfileSettings();
	
	return ELR_NoInterrupt;
}

static function CheckForSuccessfulAmbush(XComGameState NewGameState)
{
	local XComGameState_AchievementData AchievementData;
	local bool SuccessfulAmbush;
	local int UnitID;
	
	AchievementData = GlobalAchievementData(NewGameState);

	// Ambush: On the player turn, kill every AI member of a pod as the scramble away from the moment you are revealed.
	// So, if there was at least one reveled unit, and you kill them all the first turn they are revealed, it is a 
	// successful ambush.
	SuccessfulAmbush = false;
	foreach AchievementData.arrRevealedUnitsThisTurn(UnitID)
	{
		SuccessfulAmbush = true;
		if (AchievementData.arrUnitsKilledThisTurn.Find(UnitID) == INDEX_NONE)
		{
			SuccessfulAmbush = false;
			break;
		}
	}

	// Achievement: Complete a successful ambush
	if (SuccessfulAmbush)
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_Ambush);
	}
}

// This is called when a unit dies
static function OnUnitDied(XComGameState_Unit Unit, XComGameState NewGameState, Object CauseOfDeath, const out StateObjectReference SourceStateObjectRef, bool ApplyToOwnerAndComponents, const EffectAppliedData EffectData, bool bDiedInExplosion)
{
	local Name CharacterGroupName;
	local Name AbilityTemplateName;
	local X2AbilityTemplate WeaponAbilityTemplate;
	local XComGameState_AchievementData AchievementData;
	local XComGameState_Destructible DestructibleKiller;
	local Actor DestructibleActor;

	AchievementData = GlobalAchievementData(NewGameState);

	CharacterGroupName = Unit.GetMyTemplate().CharacterGroupName;
	
	if (CharacterGroupName == 'AdventPsiWitch')
	{
		// Achievement: Kill an Avatar
		`ONLINEEVENTMGR.UnlockAchievement(AT_KillAvatar);
	}
	else if (CharacterGroupName == 'Berserker')
	{
		// Achievement: Kill a Berserker in melee combat
		AbilityTemplateName = ((EffectData).AbilityInputContext).AbilityTemplateName;
		WeaponAbilityTemplate = class'X2AbilityTemplateManager'.static.GetAbilityTemplateManager().FindAbilityTemplate(AbilityTemplateName);
		if (WeaponAbilityTemplate.IsMelee())
		{
			`ONLINEEVENTMGR.UnlockAchievement(AT_KillBerserkerMelee);
		}
	}
	else if (CharacterGroupName == 'Cyberus')
	{
		AchievementData = XComGameState_AchievementData(NewGameState.CreateStateObject(class'XComGameState_AchievementData', AchievementData.ObjectID));

		AchievementData.bKilledACyberusThisMission = true;

		NewGameState.AddStateObject(AchievementData);
	}
	else if (CharacterGroupName == 'Sectoid')
	{
		// Achievement: Kill a Sectoid who is currently mind controlling a squadmate
		if (Unit.IsUnitApplyingEffectName(class'X2Effect_MindControl'.default.EffectName))
		{
			`ONLINEEVENTMGR.UnlockAchievement(AT_KillSectoidMindControlling);
		}
	}
	else if (CharacterGroupName == 'Sectopod')
	{
		// Achievement: Kill a Sectopod on the same turn you encounter it
		if (AchievementData.arrRevealedUnitsThisTurn.Find(Unit.ObjectID) != INDEX_NONE)
		{
			`ONLINEEVENTMGR.UnlockAchievement(AT_InstaKillSectopod);
		}
	}
	else if (CharacterGroupName == 'Viper')
	{
		// Achievement: Kill a Viper who is strangling a squadmate
		if (Unit.IsUnitApplyingEffectName(class'X2Ability_Viper'.default.BindSustainedEffectName) ||
			Unit.IsUnitApplyingEffectName(class'X2Ability_Viper'.default.BindAbilityName))
		{
			`ONLINEEVENTMGR.UnlockAchievement(AT_KillViperStrangling);
		}
	}

	// Achievement: Cause an enemy to fall to its death
	if (NewGameState.GetContext().IsA('XComGameStateContext_Falling') && Unit.GetTeam() == eTeam_Alien)
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_KillViaFalling);
	}

	// Achievement: Cause an enemy to die in a car explosion
	if (Unit.GetTeam() == eTeam_Alien)
	{
		if (bDiedInExplosion)
		{
			DestructibleKiller = XComGameState_Destructible(`XCOMHISTORY.GetGameStateForObjectID(SourceStateObjectRef.ObjectID));
			if (DestructibleKiller != none)
			{
				DestructibleActor = DestructibleKiller.GetVisualizer();
				if (DestructibleActor != none)
				{
					if (DestructibleActor.Tag == 'CarAchievement')
						`ONLINEEVENTMGR.UnlockAchievement(AT_KillViaCarExplosion);
				}
			}
		}
	}

	// Check for ambush
	AchievementData = XComGameState_AchievementData(NewGameState.CreateStateObject(class'XComGameState_AchievementData', AchievementData.ObjectID));

	AchievementData.arrUnitsKilledThisTurn.AddItem(Unit.ObjectID);
	
	NewGameState.AddStateObject(AchievementData);
	
	CheckForSuccessfulAmbush(NewGameState);
}

static function OnRevealAI(XComGameState NewGameState, int UnitObjectID)
{
	local XComGameState_AchievementData AchievementData;

	AchievementData = GlobalAchievementData(NewGameState);

	AchievementData = XComGameState_AchievementData(NewGameState.CreateStateObject(class'XComGameState_AchievementData', AchievementData.ObjectID));

	AchievementData.arrRevealedUnitsThisTurn.AddItem(UnitObjectID);

	NewGameState.AddStateObject(AchievementData);
}

// This is the callback for beating the game
static function FinalMissionOnSuccess()
{
	local bool July1stOrEarlier;
	local XComGameState_CampaignSettings Settings;
	local XComGameState_GameTime TimeState;
	local XComGameStateHistory History;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_HeadquartersAlien AlienHQ;
	local array<XComGameState_Item> InventoryItems;
	local XComGameState_Item InventoryItem;
	local XComGameState_Unit Unit;
	local StateObjectReference UnitRef;
	local name ItemTemplateName;
	local bool AllConventionalGear;

	History = `XCOMHISTORY;
	Settings = XComGameState_CampaignSettings(History.GetSingleGameStateObjectForClass(class'XComGameState_CampaignSettings'));
	XComHQ = class'UIUtilities_Strategy'.static.GetXComHQ();
	AlienHQ = class'UIUtilities_Strategy'.static.GetAlienHQ();
	
	`ONLINEEVENTMGR.UnlockAchievement(AT_OverthrowAny); // Overthrow the aliens at any difficulty level

	if (Settings.LowestDifficultySetting >= 2) // classic mode
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_OverthrowClassic); // Overthrow the aliens on Classic difficulty

		if (!class'X2StrategyGameRulesetDataStructures'.static.HasSquadSizeUpgrade()) // Beat the game on Classic+ difficulty without buying a Squad Size upgrade
		{
			`ONLINEEVENTMGR.UnlockAchievement(AT_WinGameClassicWithoutBuyingUpgrade);
		}

		TimeState = XComGameState_GameTime(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_GameTime'));
		July1stOrEarlier = class 'X2StrategyGameRulesetDataStructures'.static.LessThan(TimeState.CurrentTime, `XACHIEVEMENT_TRACKER.July1st);
		if (July1stOrEarlier) // Beat the game on Classic+ difficulty by July 1st
		{
			`ONLINEEVENTMGR.UnlockAchievement(AT_WinGameClassicPlusByDate);
		}
		if (Settings.bIronmanEnabled) // Beat the game on Classic+ difficulty in Ironman mode
		{
			`ONLINEEVENTMGR.UnlockAchievement(AT_Ironman);
		}

		// Check for beating a classic game without losing a single soldier
		if (XComHQ.DeadCrew.Length == 0 && AlienHQ.CapturedSoldiers.Length == 0) 
		{
			`ONLINEEVENTMGR.UnlockAchievement(AT_WinGameClassicPlusNoLosses);
		}
	}

	if (Settings.LowestDifficultySetting >= 3) // impossible mode
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_OverthrowImpossible); // Overthrow the aliens on Impossible difficulty
	}
	//Checking All Units to make sure they only have Conventional Gear
	AllConventionalGear = true;
	foreach XComHQ.Squad(UnitRef)
	{
		Unit = XComGameState_Unit(History.GetGameStateForObjectID(UnitRef.ObjectID));
		InventoryItems = Unit.GetAllInventoryItems(, true);
		foreach InventoryItems(InventoryItem)
		{
			if (InventoryItem.InventorySlot != eInvSlot_Backpack) // ignore any items which were picked up as loot on the mission
			{
				// If the item was auto-upgraded from a Tier 0 item, and the Tier 0 item is no longer available, they are allowed
				ItemTemplateName = InventoryItem.GetMyTemplateName();
				if (ItemTemplateName == 'AlienGrenade' ||
					ItemTemplateName == 'NanoMedikit' ||
					ItemTemplateName == 'SmokeGrenadeMk2')
				{
					continue;
				}

				//Otherwise we're making the assumption that all of a Unit's inventory should have a Tier of 0
				if (InventoryItem.GetMyTemplate().Tier > 0)
				{
					AllConventionalGear = false;
					break;
				}
			}
		}

		if (!AllConventionalGear)
			break;
	}
	if (AllConventionalGear)
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_WinGameUsingConventionalGear);
	}
}

// This is called when a unit is skulljacked
static function OnUnitSkulljacked(XComGameState_Unit TargetUnit)
{
	local name UnitGroupName;
	local bool bAllSkulljacked;
	local int i;
	local X2AchievementTracker Tracker;

	Tracker = `XACHIEVEMENT_TRACKER;
	UnitGroupName = TargetUnit.GetMyTemplate().CharacterGroupName;

	bAllSkulljacked = true;
	for (i = 0; i < Tracker.arrSkulljackedUnitGroups.Length; i++)
	{
		// Set the new unit to skulljacked
		if (Tracker.arrSkulljackedUnitGroups[i] == UnitGroupName)
		{
			`XPROFILESETTINGS.Data.arrbSkulljackedUnits[i] = true;
		}

		// In the same loop, check if all units are skulljacked
		if (!`XPROFILESETTINGS.Data.arrbSkulljackedUnits[i])
		{
			bAllSkulljacked = false;
		}
	}

	// Achievement: Skulljack each different type of ADVENT soldier(does not have to be in same game)
	if (bAllSkulljacked)
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_SkulljackEachAdventSoldierType);
	}
}

static function EventListenerReturn OnMissionObjectiveComplete(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	local XComGameState_BattleData BattleData;
	local MissionObjectiveDefinition MissionObjective;
	local XComGameState_Unit Unit;
	local bool IsSquadConcealed;

	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}

	BattleData = XComGameState_BattleData(EventData);

	// Reach the objective item in a Guerilla Ops mission with the entire squad still concealed
	foreach BattleData.MapData.ActiveMission.MissionObjectives(MissionObjective)
	{
		if (MissionObjective.bCompleted &&
			(string(MissionObjective.ObjectiveName) == "Hack" ||
			 string(MissionObjective.ObjectiveName) == "Recover" ||
			 string(MissionObjective.ObjectiveName) == "ProtectDevice" ||
			 string(MissionObjective.ObjectiveName) == "DestroyObject"))
		{
			IsSquadConcealed = true;
			foreach `XCOMHISTORY.IterateByClassType(class'XComGameState_Unit', Unit)
			{
				if (Unit.IsPlayerControlled() && Unit.IsSoldier())
				{
					if (!Unit.IsSquadConcealed())
					{
						IsSquadConcealed = false;
						break;
					}
				}
			}

			if (IsSquadConcealed)
			{
				`ONLINEEVENTMGR.UnlockAchievement(AT_GuerillaWarfare);
			}
		}
	}

	return ELR_NoInterrupt;
}

static function EventListenerReturn OnPCSApplied(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	`ONLINEEVENTMGR.UnlockAchievement(AT_ApplyPCSUpgrade);

	return ELR_NoInterrupt;
}

static function EventListenerReturn OnWeaponUpgraded(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_Item WeaponState;
	local array<X2WeaponUpgradeTemplate> UpgradeTemplates;
	local X2WeaponUpgradeTemplate UpgradeTemplate;
	local X2WeaponTemplate WeaponTemplate;
	local bool bAllSuperior;
	local int NumUpgradeSlots;

	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}

	XComHQ = class'UIUtilities_Strategy'.static.GetXComHQ();
	WeaponState = XComGameState_Item(EventData);
	
	if(WeaponState != none)
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_UpgradeWeapon);

		WeaponTemplate = X2WeaponTemplate(WeaponState.GetMyTemplate());
		if(WeaponTemplate != none && WeaponTemplate.IsHighTech()) // First check if this is a beam weapon
		{
			UpgradeTemplates = WeaponState.GetMyWeaponUpgradeTemplates();

			NumUpgradeSlots = WeaponTemplate.NumUpgradeSlots;
			if (XComHQ.bExtraWeaponUpgrade)
				NumUpgradeSlots++;

			// Then make sure that each slot in the weapon has been equipped with an upgrade
			if(UpgradeTemplates.Length == NumUpgradeSlots)
			{
				bAllSuperior = true;

				// Then check if it has all superior upgrades
				foreach UpgradeTemplates(UpgradeTemplate)
				{
					if(UpgradeTemplate.Tier < 2)
					{
						bAllSuperior = false;
					}
				}

				if(bAllSuperior)
				{
					`ONLINEEVENTMGR.UnlockAchievement(AT_UpgradeWeaponSuperior);
				}
			}
		}
	}

	return ELR_NoInterrupt;
}

static function EventListenerReturn OnFacilityConstructionCompleted(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	local XComGameState_FacilityXCom NewFacility;
	local XComGameState_HeadquartersXCom NewXComHQ;
	local XComGameStateHistory History;
	local XComGameState_HeadquartersRoom RoomState;
	local bool bAllRoomsFilled;
	local int idx;

	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}
	
	NewFacility = XComGameState_FacilityXCom(EventData);

	if(NewFacility != none)
	{
		History = `XCOMHISTORY;
		NewXComHQ = XComGameState_HeadquartersXCom(History.GetSingleGameStateObjectForClass(class'XComGameState_HeadquartersXCom'));

		if(NewFacility.GetMyTemplateName() == 'ResistanceComms')
		{
			`ONLINEEVENTMGR.UnlockAchievement(AT_BuildResistanceComms);
		}
		else if(NewFacility.GetMyTemplateName() == 'ShadowChamber')
		{
			`ONLINEEVENTMGR.UnlockAchievement(AT_BuildShadowChamber);
		}

		bAllRoomsFilled = true;
		for(idx = 0; idx < NewXComHQ.Rooms.Length; idx++)
		{
			RoomState = XComGameState_HeadquartersRoom(History.GetGameStateForObjectID(NewXComHQ.Rooms[idx].ObjectID));

			if(RoomState.GetFacility() == none)
			{
				bAllRoomsFilled = false;
				break;
			}
		}

		if(bAllRoomsFilled)
		{
			`ONLINEEVENTMGR.UnlockAchievement(AT_BuildEverySlot);
		}
	}

	return ELR_NoInterrupt;
}

static function EventListenerReturn OnFacilityUpgradeCompleted(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	local XComGameState_FacilityUpgrade UpgradeState;

	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}

	UpgradeState = XComGameState_FacilityUpgrade(EventData);

	if (!UpgradeState.GetMyTemplate().bHidden)
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_UpgradeFacility);
	}

	return ELR_NoInterrupt;
}

static function EventListenerReturn OnPOICompleted(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}

	`ONLINEEVENTMGR.UnlockAchievement(AT_CompletePOI);

	return ELR_NoInterrupt;
}

static function EventListenerReturn OnRegionContacted(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}

	`ONLINEEVENTMGR.UnlockAchievement(AT_ContactRegion);

	return ELR_NoInterrupt;
}

static function EventListenerReturn OnOutpostBuilt(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	local XComGameStateHistory History;
	local XComGameState_Continent Continent;
	local XComGameState_WorldRegion Region;
	local StateObjectReference RegionRef;
	local bool bOutpostFound, bOutpostOnAllContinents, bEveryContinentBonus;

	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}
	
	History = `XCOMHISTORY;

	bOutpostOnAllContinents = true;
	bEveryContinentBonus = true;
	foreach History.IterateByClassType(class'XComGameState_Continent', Continent)
	{
		bOutpostFound = false;

		foreach Continent.Regions(RegionRef)
		{
			Region = XComGameState_WorldRegion(History.GetGameStateForObjectID(RegionRef.ObjectID));
			if (Region.ResistanceLevel >= eResLevel_Outpost)
			{
				bOutpostFound = true;
			}
		}

		if (!bOutpostFound)
		{
			bOutpostOnAllContinents = false;
			bEveryContinentBonus = false; // Impossible to have every continent bonus if you don't have an outpost on every continent
			break;
		}

		if (!Continent.bContinentBonusActive)
		{
			bEveryContinentBonus = false;
		}
	}

	if (bOutpostOnAllContinents)
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_BuildRadioEveryContinent);
	}

	// Achievement: Get all of the continent bonuses in a single game
	if (bEveryContinentBonus)
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_GetAllContinentBonuses);
	}

	return ELR_NoInterrupt;
}

static function EventListenerReturn OnResearchCompleted(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	local XComGameState_Tech TechState;

	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}

	TechState = XComGameState_Tech(EventData);

	if (TechState != none)
	{
		switch (TechState.GetMyTemplateName())
		{
		case 'AutopsyAdventPsiWitch':
			`ONLINEEVENTMGR.UnlockAchievement(AT_CompleteAvatarAutopsy);
			break;
		case 'ExperimentalAmmo':
		case 'ExperimentalGrenade':
		case 'ExperimentalArmor':
			`ONLINEEVENTMGR.UnlockAchievement(AT_BuildExperimentalItem);
			break;
		default:
			break;
		}
	}

	return ELR_NoInterrupt;
}

static function EventListenerReturn OnBlackMarketGoodsSold(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}

	if (`XPROFILESETTINGS.Data.m_BlackMarketSuppliesReceived >= 1000)
	{
		`ONLINEEVENTMGR.UnlockAchievement(AT_BlackMarket);
	}

	return ELR_NoInterrupt;
}

static function EventListenerReturn OnFinalMissionStarted(Object EventData, Object EventSource, XComGameState GameState, Name EventID)
{
	if (GameState.GetContext( ).InterruptionStatus == eInterruptionStatus_Interrupt)
	{
		return ELR_NoInterrupt;
	}

	`ONLINEEVENTMGR.UnlockAchievement(AT_CreateDarkVolunteer);

	return ELR_NoInterrupt;
}

function SimulateAchievementCondition(int AchievementToSimulate)
{
	local TDateTime	May1st;
	local XComGameState_BattleData Battle;
	local XComGameState_CampaignSettings Settings;
	local XComGameStateHistory History;
	local XComGameState_Unit Unit;
	local XComGameState NewGameState;

	History = `XCOMHISTORY;
	Battle = XComGameState_BattleData(`XCOMHISTORY.GetSingleGameStateObjectForClass(class'XComGameState_BattleData'));
	Settings = XComGameState_CampaignSettings(History.GetSingleGameStateObjectForClass(class'XComGameState_CampaignSettings'));
	NewGameState = History.GetStartState();

	`log("XComGameState_AchievementTracker.SimulateAchievementCondition");

	switch (AchievementToSimulate)
	{
	case AT_CompleteTutorial:
		Battle.m_bIsTutorial = true;
		break;

	case AT_BeatMissionJuneOrLater: // Beat a mission in June or later using only Rookies
		// Set each soldier to rank Rookie
		foreach History.IterateByClassType(class'XComGameState_Unit', Unit)
		{
			if (Unit.IsPlayerControlled() && Unit.IsSoldier())
			{
				Unit.ResetRankToRookie(); // Sets the ranking to 0
			}
		}

		Battle.LocalTime = July31st;
		break;

	case AT_BeatMissionSameClass: // Beat a mission on Classic+ with a squad composed entirely of soldiers of the same class (but not rookie)
		Settings.SetDifficulty(2);
		foreach History.IterateByClassType(class'XComGameState_Unit', Unit)
		{
			if (Unit.IsPlayerControlled() && Unit.IsSoldier())
			{
				Unit.ResetRankToRookie();                      // Sets the ranking to 0
				Unit.RankUpSoldier(NewGameState, 'Sharpshooter'); // Increases ranking (so not a Rookie) and sets class to 'Sharpshooter'
			}
		}
		break;

	case AT_WinGameClassicPlusByDate: // Beat the game on Classic+ difficulty by June 1st
		class'X2StrategyGameRulesetDataStructures'.static.SetTime(
			May1st, 0, 0, 0,
			5, 1,
		class'X2StrategyGameRulesetDataStructures'.default.START_YEAR
			);
		Settings.SetDifficulty(2);
		Battle.LocalTime = May1st;
		break;

	case AT_Ironman: // Beat the game on Classic+ difficulty in Ironman mode
		Settings.SetDifficulty(2);
		Settings.SetIronmanEnabled(true);
		break;

	case AT_WinGameClassicPlusNoLosses: // Beat the game on Classic+ without losing a soldier
		Settings.SetDifficulty(2);
		break;
	
	case AT_WinGameClassicWithoutBuyingUpgrade: // Beat the game on Classic+ difficulty without buying a Squad Size upgrade
		Settings.SetDifficulty(2);
		break;

	case AT_OverthrowAny: // Overthrow the aliens at any difficulty level
		Settings.SetDifficulty(1);
		break;

	case AT_OverthrowClassic: // Overthrow the aliens on Classic difficulty
		Settings.SetDifficulty(2);
		break;

	case AT_OverthrowImpossible: // Overthrow the aliens on Impossible difficulty
		Settings.SetDifficulty(3);
		break;
	}
}

