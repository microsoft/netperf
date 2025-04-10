export default function getLatestSkuInformation(context, os, test_metadata) {
    // Check if the key "SKU" exists in the test_metadata object
    if (Object.prototype.hasOwnProperty.call(test_metadata, "SKU")) {
        return test_metadata.SKU;
    }
    console.log("SKU not found in test_metadata, generating SKU based on context and OS");
    let sku = "";
    if (context === "azure") {
        sku = "Experimental_Boost4(4vCPU, 8GiB RAM)"
    } else {
        sku = "Dell PowerEdge R650 (80 logical CPUs, 128GB RAM)"
    }
    return sku;
}
