using UnrealBuildTool;

public class InstantVolumeReducer : ModuleRules
{
    public InstantVolumeReducer(ReadOnlyTargetRules Target) : base(Target)
    {
        // Shared PCHs can retain absolute __FILE__ strings from their original build.
        PCHUsage = PCHUsageMode.NoPCHs;
        PublicDependencyModuleNames.AddRange(new[] { "Core", "CoreUObject", "Engine", "SML" });
        PrivateDependencyModuleNames.AddRange(new[] { "FactoryGame", "EnhancedInput", "InputCore", "UMG", "AkAudio" });
    }
}
