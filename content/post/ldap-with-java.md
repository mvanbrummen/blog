+++
draft = true
tags = ["java", "jndi", "active directory"
]
categories = [
]
featureimage = ""
menu = ""
date = "2016-11-02T20:16:41+10:00"
title = "Querying Active Directory in Java using the JNDI"

+++

The Java naming and directory interface (JNDI) provides a way for Java programs to interact with a directory service such as Active Directory. The below example demonstrates how to build a simple object to represent the hierarchy of nested groups and users under a specified group and also handles paging of the search result to accomodate LDAP server request limits.

```java
import java.util.ArrayList;
import java.util.List;

public class ADObject {

    private String distinguishedName;
    private List<ADObject> groups;
    private List<String> users;

    public ADObject(String distinguishedName) {
        this.distinguishedName = distinguishedName;
        this.groups = new ArrayList<>();
        this.users = new ArrayList<>();
    }

    public ADObject(String distinguishedName, List<String> users) {
        this.distinguishedName = distinguishedName;
        this.groups = new ArrayList<>();
        this.users = new ArrayList<>();
        this.users.addAll(users);
    }

    public ADObject addNestedGroup(ADObject group) {
        this.groups.add(group);
        return group;
    }

    public List<String> getAllNestedUsers() {
        return getAllUsers(this);
    }

    private List<String> getAllUsers(ADObject object) {
        List<String> s = object.getUsers();
        object.getGroups().forEach(child -> {
            s.addAll(getAllUsers(child));
        });
        return s;
    }

    public void addNestedUsers(List<String> users) {
        this.users.addAll(users);
    }

    public String getDistinguishedName() {
        return distinguishedName;
    }

    public void setDistinguishedName(String distinguishedName) {
        this.distinguishedName = distinguishedName;
    }

    public List<ADObject> getGroups() {
        return groups;
    }

    public void setGroups(List<ADObject> groups) {
        this.groups = groups;
    }

    public List<String> getUsers() {
        return users;
    }

    public void setUsers(List<String> users) {
        this.users = users;
    }

}
```

```java
import javax.naming.Context;
import javax.naming.NamingEnumeration;
import javax.naming.NamingException;
import javax.naming.directory.Attribute;
import javax.naming.directory.Attributes;
import javax.naming.directory.SearchControls;
import javax.naming.directory.SearchResult;
import javax.naming.ldap.*;
import java.util.ArrayList;
import java.util.Hashtable;
import java.util.List;

public class ADService {

    private String baseSearch = "DC=corp,DC=domain,DC=com";
    private final int PAGE_SIZE = 1000;
    private LdapContext ldapContext;

    public ADService() throws Exception {
        this.ldapContext = getContext();
    }

    private LdapContext getContext() throws NamingException {
        LdapContext ctx = new InitialLdapContext(getLdapEnvironment(), null);
        ctx.setRequestControls(null);
        return ctx;
    }

    private Hashtable<String, String> getLdapEnvironment() {
        Hashtable<String, String> ldapEnv = new Hashtable<String, String>();
        ldapEnv.put(Context.INITIAL_CONTEXT_FACTORY, "com.sun.jndi.ldap.LdapCtxFactory");
        ldapEnv.put(Context.PROVIDER_URL, "ldap://ldap.corp.domain.com:389/");
        ldapEnv.put(Context.SECURITY_PRINCIPAL, "CN=S000001,OU=Service Accounts,OU=Accounts,DC=corp,DC=domain,DC=com");
        ldapEnv.put(Context.SECURITY_CREDENTIALS, "fooBar123");
        return ldapEnv;
    }

    private SearchControls getSearchControls() {
        SearchControls searchControls = new SearchControls();
        searchControls.setSearchScope(SearchControls.SUBTREE_SCOPE);
        searchControls.setTimeLimit(30000);
        searchControls.setReturningAttributes(new String[]{"distinguishedname", "cn", "member", "objectclass", "sn", "uid", "givenname"});
        return searchControls;
    }

    public ADObject getADTree(String groupDN) throws Exception {
        ldapContext = getContext();
        ADObject root = buildADTree(null, groupDN);
        ldapContext.close();
        return root;
    }

    private ADObject buildADTree(ADObject parent, String searchFilter) throws Exception {
        ADObject node = new ADObject(searchFilter);
        node.setParent(parent);
        List<String> members = new ArrayList<>();
        byte[] cookie = null;
        ldapContext.setRequestControls(new Control[]{new PagedResultsControl(PAGE_SIZE, Control.NONCRITICAL)});
        NamingEnumeration<?> namingEnum;
        SearchControls searchControls = getSearchControls();
        do {
            // query for an AD object that's a member of the searched group and is not disabled
            namingEnum = ldapContext.search(baseSearch, String.format(
                    "(&(memberOf=%s)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))", searchFilter), searchControls);
            while (namingEnum != null && namingEnum.hasMoreElements()) {
                SearchResult searchResult = (SearchResult) namingEnum.next();
                Attributes attrs = searchResult.getAttributes();
                // if the object is a group, recurse
                if (attrs.get("objectclass").contains("group")) {
                    String dn = attrs.get("distinguishedname").toString().replace("distinguishedName: ", "");
                    node.addNestedGroup(buildADTree(node, dn));
                } else {
                    Attribute uid = attrs.get("uid");
                    if (uid != null) {
                        members.add(uid.toString());
                    }
                }
            }
            Control[] controls = ldapContext.getResponseControls();
            if (controls != null) {
                for (int i = 0; i < controls.length; i++) {
                    if (controls[i] instanceof PagedResultsResponseControl) {
                        PagedResultsResponseControl prrc = (PagedResultsResponseControl) controls[i];
                        cookie = prrc.getCookie();
                    }
                }
            }
            ldapContext.setRequestControls(new Control[]{new PagedResultsControl(pageSize, cookie, Control.CRITICAL)});
        } while (cookie != null);
        namingEnum.close();
        node.addNestedUsers(members);
        return node;
    }

}
```

```java
public class TestAD {
    public static void main(String[] args) throws Exception {
        ADService service = new ADService();
        ADObject o = service.getADTree("CN=FooBar-Users,OU=Role Groups,OU=Groups,DC=corp,DC=domain,DC=com");
    }
}
```
