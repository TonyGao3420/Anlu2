<?xml version="1.0" encoding="UTF-8"?>
<Project Version="3" Minor="2" Path="D:/Anlogic/Anlu2/prj">
    <Project_Created_Time></Project_Created_Time>
    <TD_Encoding>GB2312</TD_Encoding>
    <TD_Version>6.2.168116</TD_Version>
    <Name>Anlu2</Name>
    <HardWare>
        <Family>PH1</Family>
        <Device>PH1P35MDG324</Device>
        <Speed>-3</Speed>
    </HardWare>
    <Source_Files>
    </Source_Files>
    <FileSets>
        <FileSet Name="design_1" Type="DesignFiles">
        </FileSet>
        <FileSet Name="constraint_1" Type="ConstrainFiles">
        </FileSet>
    </FileSets>
    <TOP_MODULE>
        <LABEL></LABEL>
        <MODULE></MODULE>
        <CREATEINDEX></CREATEINDEX>
    </TOP_MODULE>
    <Property>
        <SimProperty>
            <simulator_location>D:/altera/14.1/modelsim_ase/win32aloem/vsim.exe</simulator_location>
        </SimProperty>
    </Property>
    <Device_Settings>
    </Device_Settings>
    <Configurations>
    </Configurations>
    <Runs>
        <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="" Active="true">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
    </Runs>
    <Project_Settings>
    </Project_Settings>
</Project>
