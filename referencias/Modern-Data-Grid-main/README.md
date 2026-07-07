# Modern Data Grid

- **Optimized for Canvas Apps**
- **Responsive**
- **Works Seamlessly with Any Data Source**
- **Includes Built-In Filtering, Sorting, and Keyword Search**
- **Supports Pagination** (Ensure "Default Rows" is set above 0 for it to display)

For any issues or feedback, please use the "Issues" tab at the top of the page.

![modernDataGrid - Promo](https://github.com/user-attachments/assets/5e1b4db6-ed2b-4a42-bc7c-07d49cb9b159)


## Installation

To ensure the custom component runs properly, you must first enable code components for Canvas Apps.

### Enabling Code Components for Canvas Apps
1. Navigate to [Power Platform Admin Center](https://admin.powerplatform.microsoft.com).
2. Select **Environments** from the navigation menu on the left.
3. Click **Settings** from the ribbon.
   ![modernDataGrid_7](https://github.com/user-attachments/assets/be53be87-54dd-4a2b-a88c-c63284a3890e)
5. Under the **Product** section, select **Features**.
   ![modernDataGrid_6](https://github.com/user-attachments/assets/72568470-6f6c-4b00-9be9-052d401a8d9b)
7. Enable **Allow publishing of canvas apps with code components** under the **Power Apps component framework for canvas apps**.
   ![modernDataGrid_5](https://github.com/user-attachments/assets/1c1b1c4a-22ff-455d-8cfa-5a4a165d2b86)

### Importing the Solution to Your Environment
1. Download the latest solution for this component from the [Modern Data Grid releases](https://github.com/GorgonUK/Modern-Data-Grid/releases).
2. Go to [Power Apps Maker Portal](https://make.powerapps.com).
   ![modernDataGrid_4](https://github.com/user-attachments/assets/ea55fa6b-3ee9-4a6e-8f58-03479f5346d7)
4. Click **Import solution** from the ribbon and follow the prompts.

### Adding the Code Component to Your Canvas App
1. Open your Canvas App in **Edit mode**.
2. Click the magnifying glass icon in the **Insert** tab.
   ![modernDataGrid_3](https://github.com/user-attachments/assets/64f08c80-2042-43db-b0cc-5717169fb062)
4. Select the **Code** tab.
5. Choose **ModernDataGrid** from the list.
   ![modernDataGrid_2](https://github.com/user-attachments/assets/af9e0a95-b590-41c7-a52d-8b5fcb57003e)
7. Click **Insert**.
8. The component is now ready for use in your Canvas App.
   ![modernDataGrid_1](https://github.com/user-attachments/assets/b35ca823-4bc3-4544-be02-b19fd31daa21)


## Input Parameters

| Input              | Values                                        |
|--------------------|-----------------------------------------------|
| `enabled`          | `true`, `false`                               |
| `displayHeader`    | `true`, `false`                               |
| `headerText`       | Custom text string                            |
| `displaySearch`    | `true`, `false`                               |
| `displayPagination`| `true`, `false`                               |
| `allowFiltering`   | `true`, `false`                               |
| `allowSorting`     | `true`, `false`                               |
| `defaultRows`      | Numeric value (e.g., `10`, `25`, `50`)        |
| `emptyMessage`     | Custom text string                            |
| `selectionMode`    | `multiple`, `checkbox`                        |
| `filterDisplayType`| `menu`, `row`                                 |
