import buildStaticRoute from 'nilavu/routes/build-static-route';

const SignupRoute = buildStaticRoute('signup');

SignupRoute.reopen({
  beforeModel() {
    var canSignUp = this.controllerFor("application").get('canSignUp');
    alert("--- signup");
    if (!this.siteSettings.login_required) {
      this.replaceWith('discovery.latest').then(e => {
        if (canSignUp) {
          Ember.run.next(() => e.send('showCreateAccount'));
        }
      });
    } else {
      this.replaceWith('login').then(e => {
        if (canSignUp) {
          alert("--- signup now");
          Ember.run.next(() => e.send('showCreateAccount'));
        }
      });
    }
  }
});

export default SignupRoute;