#pragma once

#include "CoreMinimal.h"
#include "Subsystems/WorldSubsystem.h"
#include "Module/GameInstanceModule.h"
#include "InstantVolumeReducerSubsystem.generated.h"

class AFGPlayerController;
class AFGCharacterPlayer;
class UEnhancedInputComponent;
class UInputMappingContext;
class UInputAction;
class UInputComponent;

UCLASS(Abstract)
class INSTANTVOLUMEREDUCER_API UInstantVolumeReducerGameInstanceModule : public UGameInstanceModule
{
    GENERATED_BODY()
public:
    UPROPERTY(EditDefaultsOnly, Category = "Input")
    TObjectPtr<UInputMappingContext> MappingContext;

    UPROPERTY(EditDefaultsOnly, Category = "Input")
    TObjectPtr<UInputAction> ToggleAction;
};

/** Local audio only; never replicated or written to a savegame. */
UCLASS()
class INSTANTVOLUMEREDUCER_API UInstantVolumeReducerSubsystem : public UWorldSubsystem
{
    GENERATED_BODY()
public:
    virtual bool DoesSupportWorldType(EWorldType::Type WorldType) const override;
    virtual bool ShouldCreateSubsystem(UObject* Outer) const override;
    virtual void Initialize(FSubsystemCollectionBase& Collection) override;
    virtual void Deinitialize() override;
    void OnMasterVolumeUpdated();
private:
    bool CaptureNormalVolume();
    void RefreshVolume();
    void Toggle();
    void DetachInput();
    void OnPlayerInputInitialized(AFGCharacterPlayer* Character, UInputComponent* InputComponent);
    void OnPlayerInputDestroyed(AFGCharacterPlayer* Character);
    int32 GetReduction() const;
    UFUNCTION() void OnReductionChanged();
    bool bEnabled = false;
    float NormalMasterVolume = 0.f;
    TWeakObjectPtr<UEnhancedInputComponent> Input;
    TWeakObjectPtr<AFGCharacterPlayer> InputCharacter;
    uint32 InputBindingHandle = 0;
    UPROPERTY() TObjectPtr<class UConfigPropertyInteger> ReductionProperty;
    TWeakObjectPtr<AFGPlayerController> Controller;
    FDelegateHandle InputInitializedHandle;
    FDelegateHandle InputDestroyedHandle;
};
