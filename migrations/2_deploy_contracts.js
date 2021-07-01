const KuDoge = artifacts.require("KuDoge");

module.exports = async function(deployer) {
    await deployer.deploy(KuDoge);
    const iKuDoge = await KuDoge.deployed();
    console.log(iKuDoge.address);

    //0xc0fFee0000C824D24E0F280f1e4D21152625742b
    //await iKuDoge.setRouterAddress("0xc0fFee0000C824D24E0F280f1e4D21152625742b", {gas: 5500000});

};
