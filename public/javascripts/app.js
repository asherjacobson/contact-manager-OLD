function togglePassword() {
    var x = document.getElementById("password");
    var y = document.getElementById("confirm_password") || {};
    if (x.type === "password") {
        x.type = "text";
        y.type = "text";
    } else {
        x.type = "password";
        y.type = "password";
    }
}
