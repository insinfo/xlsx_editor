import { IInputs, IOutputs } from "./generated/ManifestTypes";
import DataSetInterfaces = ComponentFramework.PropertyHelper.DataSetApi;
import * as React from "react";
type DataSet = ComponentFramework.PropertyTypes.DataSet;
import DataGrid from "./components/DataGrid";

export class ModernDataGrid implements ComponentFramework.ReactControl<IInputs, IOutputs> {
    private container: HTMLDivElement;
    private notifyOutputChanged: () => void;
    constructor() {}

    public init(
        context: ComponentFramework.Context<IInputs>,
        notifyOutputChanged: () => void,
        state: ComponentFramework.Dictionary,
        container: HTMLDivElement
    ): void {
        console.log("Modern Data Grid 1.7");
        this.container = container;
        this.notifyOutputChanged = notifyOutputChanged;
    }
    public updateView(
        context: ComponentFramework.Context<IInputs>
      ): React.ReactElement {
        return React.createElement(DataGrid, {context:context,notifyOutputChanged: this.notifyOutputChanged});
    }

    public getOutputs(): IOutputs {
        return {};
    }

    public destroy(): void {
    }
}
