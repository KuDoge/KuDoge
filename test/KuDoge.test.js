const { expectRevert, time } = require('@openzeppelin/test-helpers');
const KuDoge = artifacts.require('KuDoge');

contract('KuDoge', ([owner, bob, carol, alice]) => {
    beforeEach(async () => {
        this.KuDoge = await KuDoge.new();  
    });

    it('transfer without fee', async () => {
      await this.KuDoge.transfer(alice, "10000", { from: owner });
      assert.equal((await this.KuDoge.balanceOf(alice)).toString(), "10000");     
    })  
    
    it('transfer with fee', async () => {
      await this.KuDoge.transfer(alice, "10000", { from: owner });
      await this.KuDoge.transfer(carol, "10000", { from: alice });
      assert.equal((await this.KuDoge.balanceOf(carol)).toString(), "9100");
      assert.equal((await this.KuDoge.balanceOf(this.KuDoge.address)).toString(), "700");
      assert.equal((await this.KuDoge.totalSupply()).toString(), "999999999999999999999999999999800");      
    })  
});

