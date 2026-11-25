#include "InstantVolumeReducerSubsystem.h"
#include "AkAudioDevice.h"
#include "Configuration/ConfigManager.h"
#include "Configuration/Properties/ConfigPropertyInteger.h"
#include "Engine/GameInstance.h"
#include "EnhancedInputComponent.h"
#include "FGPlayerController.h"
#include "FGCharacterPlayer.h"
#include "Module/GameInstanceModuleManager.h"
#include "ModLoading/PluginModuleLoader.h"
#include "UI/FGGameUI.h"
#include "InputAction.h"
#include "InputMappingContext.h"

#define LOCTEXT_NAMESPACE "InstantVolumeReducer"
DEFINE_LOG_CATEGORY_STATIC(LogInstantVolumeReducer, Log, All);

bool UInstantVolumeReducerSubsystem::ShouldCreateSubsystem(UObject* Outer) const
{
    return !IsRunningDedicatedServer() && Super::ShouldCreateSubsystem(Outer);
}

bool UInstantVolumeReducerSubsystem::DoesSupportWorldType(EWorldType::Type Type) const
{
    return Type == EWorldType::Game || Type == EWorldType::PIE;
}

void UInstantVolumeReducerSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
    Super::Initialize(Collection);
    InputInitializedHandle = AFGCharacterPlayer::OnPlayerInputInitialized.AddUObject(
        this, &UInstantVolumeReducerSubsystem::OnPlayerInputInitialized);
    InputDestroyedHandle = AFGCharacterPlayer::OnPlayerInputDestroyed.AddUObject(
        this, &UInstantVolumeReducerSubsystem::OnPlayerInputDestroyed);
}

void UInstantVolumeReducerSubsystem::OnPlayerInputInitialized(AFGCharacterPlayer* Character, UInputComponent* InputComponent)
{
    if (!Character || Character->GetWorld() != GetWorld() || FPluginModuleLoader::IsMainMenuWorld(GetWorld())) return;
    auto* PC = Cast<AFGPlayerController>(Character->GetController());
    auto* EnhancedInput = Cast<UEnhancedInputComponent>(InputComponent);
    if (!PC || !PC->IsLocalController() || !EnhancedInput) return;
    auto* Manager = GetWorld()->GetGameInstance()->GetSubsystem<UGameInstanceModuleManager>();
    auto* Module = Cast<UInstantVolumeReducerGameInstanceModule>(Manager->FindModule(TEXT("InstantVolumeReducer")));
    if (!Module || !Module->MappingContext || !Module->ToggleAction)
    {
        UE_LOG(LogInstantVolumeReducer, Error, TEXT("Root module input assets are not configured"));
        return;
    }
    DetachInput();
    Controller = PC;
    InputCharacter = Character;
    Input = EnhancedInput;
    InputBindingHandle = EnhancedInput->BindAction(Module->ToggleAction, ETriggerEvent::Started,
        this, &UInstantVolumeReducerSubsystem::Toggle).GetHandle();
    (void)PC->BindMappingContext(Module->MappingContext, 0, this);

    FConfigId Id;
    Id.ModReference = TEXT("InstantVolumeReducer");
    auto* ConfigManager = GetWorld()->GetGameInstance()->GetSubsystem<UConfigManager>();
    if (ReductionProperty)
        ReductionProperty->OnPropertyValueChanged.RemoveDynamic(this, &UInstantVolumeReducerSubsystem::OnReductionChanged);
    auto* Root = ConfigManager->GetConfigurationRootSection(Id);
    ReductionProperty = Root ? Cast<UConfigPropertyInteger>(Root->SectionProperties.FindRef(TEXT("ReductionPercent"))) : nullptr;
    if (ReductionProperty)
        ReductionProperty->OnPropertyValueChanged.AddDynamic(this, &UInstantVolumeReducerSubsystem::OnReductionChanged);
}

void UInstantVolumeReducerSubsystem::OnPlayerInputDestroyed(AFGCharacterPlayer* Character)
{
    if (InputCharacter.Get() == Character) DetachInput();
}

int32 UInstantVolumeReducerSubsystem::GetReduction() const
{
    return ReductionProperty ? FMath::Clamp(ReductionProperty->Value, 5, 95) : 50;
}

bool UInstantVolumeReducerSubsystem::CaptureNormalVolume()
{
    auto* Audio = FAkAudioDevice::Get();
    auto Scope = AK::SoundEngine::Query::RTPCValue_Global;
    float Value = 0.f;
    if (!Audio || Audio->GetRTPCValue(TEXT("Menu_Volume_Master"), AK_INVALID_GAME_OBJECT,
        AK_INVALID_PLAYING_ID, Value, Scope) != AK_Success || !FMath::IsFinite(Value))
    {
        UE_LOG(LogInstantVolumeReducer, Warning, TEXT("Could not read the live master volume; leaving audio unchanged"));
        return false;
    }
    NormalMasterVolume = Value;
    return true;
}

void UInstantVolumeReducerSubsystem::OnMasterVolumeUpdated()
{
    // The original game callback has applied the user's new normal volume.
    if (bEnabled && CaptureNormalVolume()) RefreshVolume();
}

void UInstantVolumeReducerSubsystem::RefreshVolume()
{
    // Scale the actual Wwise value, without changing or saving game options.
    if (auto* Audio = FAkAudioDevice::Get())
    {
        const float Target = NormalMasterVolume * (bEnabled ? 1.f - GetReduction() / 100.f : 1.f);
        const auto Result = Audio->SetRTPCValue(TEXT("Menu_Volume_Master"), Target, 0, nullptr);
        if (Result != AK_Success)
            UE_LOG(LogInstantVolumeReducer, Warning, TEXT("Master volume update failed: %d"), static_cast<int32>(Result));
    }
}

void UInstantVolumeReducerSubsystem::OnReductionChanged() { if (bEnabled) RefreshVolume(); }

void UInstantVolumeReducerSubsystem::Toggle()
{
    if (!Controller.IsValid() || GetWorld()->IsPaused()) return;
    if (!bEnabled && !CaptureNormalVolume()) return;
    bEnabled = !bEnabled;
    RefreshVolume();
    if (auto* GameUI = Controller->GetGameUI())
    {
        GameUI->ShowTextNotification(bEnabled
            ? LOCTEXT("Enabled", "Instant Volume Reducer: On")
            : LOCTEXT("Disabled", "Instant Volume Reducer: Off"));
    }
    else
    {
        UE_LOG(LogInstantVolumeReducer, Warning, TEXT("Game UI unavailable; toggle notification skipped"));
    }
}

void UInstantVolumeReducerSubsystem::DetachInput()
{
    if (auto* PC = Controller.Get())
    {
        PC->UnbindAllMappingContextsByObject(this);
    }
    if (auto* EnhancedInput = Input.Get()) EnhancedInput->RemoveBindingByHandle(InputBindingHandle);
    Input.Reset();
    InputCharacter.Reset();
    InputBindingHandle = 0;
    Controller.Reset();
}

void UInstantVolumeReducerSubsystem::Deinitialize()
{
    AFGCharacterPlayer::OnPlayerInputInitialized.Remove(InputInitializedHandle);
    AFGCharacterPlayer::OnPlayerInputDestroyed.Remove(InputDestroyedHandle);
    if (bEnabled) { bEnabled = false; RefreshVolume(); }
    if (ReductionProperty) ReductionProperty->OnPropertyValueChanged.RemoveDynamic(this, &UInstantVolumeReducerSubsystem::OnReductionChanged);
    DetachInput();
    Super::Deinitialize();
}
#undef LOCTEXT_NAMESPACE
