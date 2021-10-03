var samalrt = {};

samalrt.List = class List {
    constructor(value, next) {
        this.value = value;
        this.next = next;
    }
    equals(other) {
        let self = this;
        while(true) {
            if(self === null && other === null)
                return true;
            if(self === null || other === null) {
                return false;
            }
            if((self.value === null && other.value !== null) || (self.value !== null && other.value === null)) {
                return false;
            }
            if(self.value === null && other.value === null) {
                // both sides are an empty list or pointer or so, so both values are equal
            } else if(self.value.equals !== undefined) {
                if(!self.value.equals(other.value)) {
                    return false;
                }
            } else {
                if(self.value !== other.value) {
                    return false;
                }
            }
            self = self.next;
            other = other.next;
        }
    }
}

samalrt.SamalContext = class SamalContext {

}