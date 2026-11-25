#include "InstantVolumeReducerSubsystem.h"
#include "Modules/ModuleManager.h"
#include "Patching/NativeHookManager.h"
#include "FGGameUserSettings.h"
#include "UObject/UObjectIterator.h"

class FInstantVolumeReducerModule : public FDefaultGameModuleImpl
{
    virtual void StartupModule() override
    {
        if (!WITH_EDITOR)
        {
            SUBSCRIBE_METHOD_AFTER(UFGGameUserSettings::UpdateAudioOption,
                [](UFGGameUserSettings*, FString CVar)
                {
                    if (CVar == TEXT("RTPC.Menu_Volume_Master"))
                        for (TObjectIterator<UInstantVolumeReducerSubsystem> It; It; ++It)
                            if (!It->IsTemplate()) It->OnMasterVolumeUpdated();
                });
        }
    }
};
IMPLEMENT_GAME_MODULE(FInstantVolumeReducerModule, InstantVolumeReducer);
