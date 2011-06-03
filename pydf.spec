Summary:        Fully colorized df clone written in python
Name:           pydf
Version:        9
Release:        4%{?dist}
License:        Public Domain
Group:          Applications/System
Source:         http://kassiopeia.juls.savba.sk/~garabik/software/%{name}/%{name}_9.tar.gz
URL:            http://kassiopeia.juls.savba.sk/~garabik/software/%{name}/
Requires:       python >= 2.3
BuildArch:      noarch

%description
pydf displays the amount of used and available space on your file systems,
just like df, but in colors. The output format is completely customizable.

%prep
%setup -q

%build

%install
rm -rf $RPM_BUILD_ROOT
install -d $RPM_BUILD_ROOT{%{_bindir},%{_sysconfdir},%{_mandir}/man1}

install -p pydf   $RPM_BUILD_ROOT%{_bindir}
install -p pydfrc $RPM_BUILD_ROOT%{_sysconfdir}
install -p pydf.1 $RPM_BUILD_ROOT%{_mandir}/man1

gzip -9nf $RPM_BUILD_ROOT%{_mandir}/man1/pydf.1 README

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(644,root,root,755)
%doc README.gz INSTALL COPYING
%attr(755,root,root) %{_bindir}/pydf
%config(noreplace) %{_sysconfdir}/pydfrc

%{_mandir}/man1/pydf.1.gz

%changelog

* Mon May 2 2011 Clint Savage <herlo@fedoraproject.org> 9-3
- Removing define and properly adding other docs

* Sun May 1 2011 Clint Savage <herlo@fedoraproject.org> 9-2
- Fixing minor packaging issues

* Fri Apr 29 2011 Clint Savage <herlo@fedoraproject.org> 9-1
- Initial package build
